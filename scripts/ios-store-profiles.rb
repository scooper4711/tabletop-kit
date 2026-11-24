#!/usr/bin/env ruby
# frozen_string_literal: true

# Makes sure each bundle identifier has an App Store provisioning profile, named "<prefix><bundle-id>", for an Apple
# Distribution certificate in the keychain, and installs it where Xcode looks. A profile that still works is reused; one
# that doesn't is deleted and made again. It never creates a certificate. Specified in docs/specs/store-listing.
#
# Usage: ios-store-profiles.rb <name-prefix> <bundle-id>...
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE   the App Store Connect API key
# PROFILES_DIR   where to install them (default: Xcode's ~/Library/Developer/Xcode/UserData/Provisioning Profiles)

require 'fileutils'
require 'open3'
require 'time'
require_relative 'app_store_connect_client'

class ProfileError < AppStoreConnectError; end

# The serial numbers of the valid Apple Distribution identities in the keychain search list.
module DistributionKeychain
  NAME = 'Apple Distribution'

  def self.serial_numbers
    valid = identity_hashes
    certificates.select { |hash, _| valid.include?(hash) }.map { |_, pem| serial_number(pem) }
  end

  def self.identity_hashes
    run('find-identity', '-v', '-p', 'codesigning')
      .scan(/^\s*\d+\) ([0-9A-F]{40}) "#{NAME}:/).flatten
  end

  # `find-certificate -Z -p` prints each certificate's SHA-1 line before its PEM.
  def self.certificates
    run('find-certificate', '-a', '-Z', '-p', '-c', NAME)
      .scan(/SHA-1 hash: ([0-9A-F]{40}).*?(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)/m)
  end

  def self.serial_number(pem)
    OpenSSL::X509::Certificate.new(pem).serial.to_s(16)
  end

  def self.run(*arguments)
    output, status = Open3.capture2('security', *arguments)
    raise ProfileError, "security #{arguments.first} failed" unless status.success?

    output
  end
end

# Finds or makes the App Store profile of each bundle identifier.
class StoreProfiles
  TYPE = 'IOS_APP_STORE'
  MINIMUM_DAYS_LEFT = 7

  def initialize(client, serial_numbers:, profiles_dir:, log: ->(line) { warn line })
    @client = client
    @serial_numbers = serial_numbers.map { |serial| normalize(serial) }
    @profiles_dir = profiles_dir
    @log = log
  end

  def install(prefix, bundle_ids)
    certificate = distribution_certificate
    bundle_ids.each do |bundle_id|
      profile = usable_profile("#{prefix}#{bundle_id}", certificate) ||
                create_profile("#{prefix}#{bundle_id}", bundle_id, certificate)
      write(profile)
    end
  end

  private

  def distribution_certificate
    certificates = @client.get('/v1/certificates', 'limit' => 200)
    certificate = certificates.find { |item| known_serial?(item.dig('attributes', 'serialNumber')) }
    certificate&.fetch('id') || raise(ProfileError, 'no keychain distribution certificate is in App Store Connect')
  end

  # Deletes this name's profiles that are invalid, about to expire or for another certificate. Returns one that's left.
  def usable_profile(name, certificate)
    profiles = @client.get('/v1/profiles', 'filter[name]' => name, 'filter[profileType]' => TYPE, 'limit' => 200)
    usable, stale = profiles.select { |profile| profile.dig('attributes', 'name') == name }
                            .partition { |profile| usable?(profile, certificate) }
    stale.each do |profile|
      @log.call("Deleting the stale profile #{name} (#{profile.dig('attributes', 'uuid')})")
      @client.delete("/v1/profiles/#{profile.fetch('id')}")
    end
    usable.first
  end

  def usable?(profile, certificate)
    attributes = profile.fetch('attributes')
    return false unless attributes['profileState'] == 'ACTIVE'
    return false if Time.parse(attributes.fetch('expirationDate')) < Time.now + (MINIMUM_DAYS_LEFT * 86_400)

    @client.get("/v1/profiles/#{profile.fetch('id')}/certificates", 'limit' => 200)
           .any? { |item| item.fetch('id') == certificate }
  end

  def create_profile(name, bundle_id, certificate)
    @log.call("Making the profile #{name}")
    @client.post('/v1/profiles', data: {
                   type: 'profiles',
                   attributes: { name: name, profileType: TYPE },
                   relationships: {
                     bundleId: { data: { type: 'bundleIds', id: bundle_id_resource(bundle_id) } },
                     certificates: { data: [{ type: 'certificates', id: certificate }] }
                   }
                 }).fetch('data')
  end

  # A bundle identifier can be registered once per platform; an iOS profile needs the iOS or universal one.
  def bundle_id_resource(bundle_id)
    matches = @client.get('/v1/bundleIds', 'filter[identifier]' => bundle_id, 'limit' => 200)
                     .select { |item| item.dig('attributes', 'identifier') == bundle_id }
    match = matches.find { |item| item.dig('attributes', 'platform') != 'MAC_OS' } || matches.first
    match&.fetch('id') || raise(ProfileError, "App Store Connect has no bundle identifier #{bundle_id}")
  end

  def write(profile)
    attributes = profile.fetch('attributes')
    FileUtils.mkdir_p(@profiles_dir)
    path = File.join(@profiles_dir, "#{attributes.fetch('uuid')}.mobileprovision")
    File.binwrite(path, Base64.decode64(attributes.fetch('profileContent')))
    @log.call("Installed #{attributes.fetch('name')}")
  end

  def known_serial?(serial)
    @serial_numbers.include?(normalize(serial))
  end

  def normalize(serial)
    serial.to_s.upcase.sub(/\A0+/, '')
  end
end

def install_store_profiles(arguments)
  prefix, *bundle_ids = arguments
  raise ProfileError, 'usage: ios-store-profiles.rb <name-prefix> <bundle-id>...' if bundle_ids.empty?

  client = AppStoreConnectClient.new(key_id: ENV.fetch('ASC_KEY_ID'), issuer_id: ENV.fetch('ASC_ISSUER_ID'),
                                     key_file: ENV.fetch('ASC_KEY_FILE'))
  profiles_dir = ENV.fetch('PROFILES_DIR', File.expand_path('~/Library/Developer/Xcode/UserData/Provisioning Profiles'))
  StoreProfiles.new(client, serial_numbers: DistributionKeychain.serial_numbers, profiles_dir: profiles_dir)
               .install(prefix, bundle_ids)
end

if $PROGRAM_NAME == __FILE__
  begin
    install_store_profiles(ARGV)
  rescue AppStoreConnectError, KeyError, SystemCallError => e
    warn "ios-store-profiles: #{e.message}"
    exit 1
  end
end
