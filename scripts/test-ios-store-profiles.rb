#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs ios-store-profiles.rb's profile handling against a stand-in for App Store Connect. Nothing is sent anywhere.

require 'minitest/autorun'
require 'tmpdir'
require_relative 'ios-store-profiles'

# Answers like App Store Connect for profiles and records every write.
class FakeProfileService
  attr_reader :posts, :deletes
  attr_accessor :profiles, :bundle_ids

  def initialize
    @posts = []
    @deletes = []
    @profiles = []
    @profile_certificates = {}
    @bundle_ids = [bundle_id('mac', 'io.example.App', 'MAC_OS'), bundle_id('ios', 'io.example.App', 'IOS'),
                   bundle_id('ext', 'io.example.App.Widget', 'UNIVERSAL'),
                   bundle_id('other', 'io.example.App.Widget.Old', 'IOS')]
  end

  def add_profile(id, name:, state: 'ACTIVE', days_left: 300, certificate: 'dist')
    @profiles << profile(id, name, state, days_left)
    @profile_certificates[id] = [{ 'id' => certificate }]
  end

  def get(path, params = {})
    case path
    when '/v1/certificates' then [certificate('dev', '1F'), certificate('dist', '0A1B2C')]
    when '/v1/profiles' then @profiles.select { |item| item.dig('attributes', 'name') == params['filter[name]'] }
    when '/v1/bundleIds' then matching_bundle_ids(params['filter[identifier]'])
    when %r{\A/v1/profiles/(\w+)/certificates\z} then @profile_certificates.fetch(Regexp.last_match(1))
    else raise "unexpected GET #{path}"
    end
  end

  def post(path, body)
    @posts << [path, body]
    name = body.dig(:data, :attributes, :name)
    { 'data' => profile("new#{@posts.size}", name, 'ACTIVE', 365) }
  end

  def delete(path)
    @deletes << path
    {}
  end

  private

  # Like App Store Connect, the identifier filter also gives longer identifiers that start with it.
  def matching_bundle_ids(prefix)
    @bundle_ids.select { |item| item.dig('attributes', 'identifier').start_with?(prefix) }
  end

  def certificate(id, serial)
    { 'id' => id, 'attributes' => { 'serialNumber' => serial } }
  end

  def bundle_id(id, identifier, platform)
    { 'id' => id, 'attributes' => { 'identifier' => identifier, 'platform' => platform } }
  end

  def profile(id, name, state, days_left)
    { 'id' => id, 'attributes' => {
      'name' => name, 'profileState' => state, 'uuid' => "uuid-#{id}",
      'expirationDate' => (Time.now + (days_left * 86_400)).utc.iso8601,
      'profileContent' => Base64.strict_encode64(name)
    } }
  end
end

# Checks which profiles are reused, replaced or made, and what is installed.
class StoreProfilesTest < Minitest::Test
  PREFIX = 'CI '

  def setup
    @service = FakeProfileService.new
    @dir = Dir.mktmpdir
    @logged = []
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_a_missing_profile_is_made_for_the_keychain_certificate_and_the_ios_bundle_id
    install('io.example.App')
    path, body = @service.posts.first
    assert_equal '/v1/profiles', path
    assert_equal({ name: 'CI io.example.App', profileType: 'IOS_APP_STORE' }, body.dig(:data, :attributes))
    assert_equal 'ios', body.dig(:data, :relationships, :bundleId, :data, :id)
    assert_equal [{ type: 'certificates', id: 'dist' }], body.dig(:data, :relationships, :certificates, :data)
  end

  def test_a_made_profile_is_installed_under_its_uuid
    install('io.example.App')
    assert_equal 'CI io.example.App', File.binread(File.join(@dir, 'uuid-new1.mobileprovision'))
  end

  def test_installing_removes_other_files_of_the_same_name
    File.write(File.join(@dir, 'replaced.mobileprovision'), 'CI io.example.App')
    File.write(File.join(@dir, 'unrelated.mobileprovision'), 'Someone else')
    install('io.example.App')
    assert_equal %w[unrelated.mobileprovision uuid-new1.mobileprovision], Dir.children(@dir).sort
  end

  def test_an_unreadable_expiration_date_stops
    @service.add_profile('odd', name: 'CI io.example.App')
    @service.profiles.last['attributes']['expirationDate'] = 'someday'
    error = assert_raises(ProfileError) { install('io.example.App') }
    assert_match(/expiration date/, error.message)
  end

  def test_each_bundle_id_gets_its_own_profile
    install('io.example.App', 'io.example.App.Widget')
    assert_equal(['CI io.example.App', 'CI io.example.App.Widget'],
                 @service.posts.map { |_, body| body.dig(:data, :attributes, :name) })
    assert_equal 'ext', @service.posts.last.last.dig(:data, :relationships, :bundleId, :data, :id)
  end

  def test_a_working_profile_is_reused
    @service.add_profile('kept', name: 'CI io.example.App')
    install('io.example.App')
    assert_empty @service.posts
    assert_empty @service.deletes
    assert File.exist?(File.join(@dir, 'uuid-kept.mobileprovision'))
  end

  def test_an_invalid_profile_is_replaced
    @service.add_profile('broken', name: 'CI io.example.App', state: 'INVALID')
    install('io.example.App')
    assert_equal ['/v1/profiles/broken'], @service.deletes
    assert_equal 1, @service.posts.size
  end

  def test_a_profile_about_to_expire_is_replaced
    @service.add_profile('old', name: 'CI io.example.App', days_left: 2)
    install('io.example.App')
    assert_equal ['/v1/profiles/old'], @service.deletes
  end

  def test_a_profile_for_another_certificate_is_replaced
    @service.add_profile('other', name: 'CI io.example.App', certificate: 'retired')
    install('io.example.App')
    assert_equal ['/v1/profiles/other'], @service.deletes
  end

  def test_a_profile_with_another_name_is_left_alone
    @service.add_profile('mine', name: 'Someone else io.example.App', state: 'INVALID')
    install('io.example.App')
    assert_empty @service.deletes
  end

  def test_no_matching_certificate_stops_before_any_write
    error = assert_raises(ProfileError) { install('io.example.App', serial_numbers: ['FF']) }
    assert_match(/distribution certificate/, error.message)
    assert_empty @service.posts
  end

  def test_serial_numbers_match_without_leading_zeros_or_case
    install('io.example.App', serial_numbers: ['a1b2c'])
    assert_equal 1, @service.posts.size
  end

  def test_an_unregistered_bundle_id_stops
    @service.bundle_ids = []
    error = assert_raises(ProfileError) { install('io.example.App') }
    assert_match(/no bundle identifier io.example.App/, error.message)
  end

  def test_a_mac_only_bundle_id_stops_before_any_write
    @service.bundle_ids = @service.bundle_ids.take(1)
    error = assert_raises(ProfileError) { install('io.example.App') }
    assert_match(/macOS only/, error.message)
    assert_empty @service.posts
  end

  def test_run_wants_a_bundle_id
    assert_raises(ProfileError) { install_store_profiles(['CI ']) }
  end

  private

  def install(*bundle_ids, serial_numbers: ['A1B2C'])
    folder = ProfileFolder.new(@dir, name_of: ->(file) { File.read(file) })
    settings = ProfileSettings.new(serial_numbers: serial_numbers, folder: folder, log: ->(line) { @logged << line })
    StoreProfiles.new(@service, settings).install(PREFIX, bundle_ids)
  end
end

# Checks how an installed profile file is read.
class ProfileFolderTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_a_file_that_is_not_a_profile_has_no_name
    path = File.join(@dir, 'broken.mobileprovision')
    File.write(path, 'not a profile')
    assert_equal '', ProfileFolder.installed_name(path)
  end
end
