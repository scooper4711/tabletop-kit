#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs testflight-internal.rb's delivery against a stand-in for App Store Connect. Nothing is sent anywhere.

require 'minitest/autorun'
require_relative 'testflight-internal'

# Answers like App Store Connect and records every write.
class FakeAppStoreConnect
  attr_reader :posts, :patches
  attr_accessor :groups, :processing_states, :internal_state, :localizations

  def initialize
    @posts = []
    @patches = []
    @groups = [group('internal', true, false), group('all-builds', true, true), group('public', false, false)]
    @processing_states = ['VALID']
    @internal_state = 'IN_BETA_TESTING'
    @localizations = []
  end

  def get(path, _params = {})
    case path
    when '/v1/apps' then [{ 'id' => 'app', 'attributes' => { 'bundleId' => 'io.example.App' } }]
    when '/v1/apps/app/betaGroups' then @groups
    when '/v1/builds' then [build]
    when '/v1/builds/build/betaBuildLocalizations' then @localizations
    when '/v1/builds/build/buildBetaDetail' then { 'attributes' => { 'internalBuildState' => @internal_state } }
    else raise "unexpected GET #{path}"
    end
  end

  def post(path, body)
    @posts << [path, body]
    {}
  end

  def patch(path, body)
    @patches << [path, body]
    {}
  end

  def group(id, internal, all_builds)
    { 'id' => id, 'attributes' => { 'isInternalGroup' => internal, 'hasAccessToAllBuilds' => all_builds } }
  end

  private

  def build
    state = @processing_states.length > 1 ? @processing_states.shift : @processing_states.first
    { 'id' => 'build', 'attributes' => { 'processingState' => state } }
  end
end

class InternalTesterDeliveryTest < Minitest::Test
  REQUEST = { bundle_id: 'io.example.App', build_number: '12', notes: 'Try it', platforms: ['IOS'] }.freeze

  def setup
    @client = FakeAppStoreConnect.new
    @naps = []
    @delivery = InternalTesterDelivery.new(@client, timeout_seconds: 60, sleeper: ->(seconds) { @naps << seconds },
                                                    log: ->(_line) {})
  end

  def group_posts
    @client.posts.select { |path, _body| path.end_with?('/relationships/betaGroups') }
  end

  def test_adds_the_build_only_to_the_internal_group_without_automatic_access
    @delivery.deliver(REQUEST)
    assert_equal 1, group_posts.length
    assert_equal ['internal'], group_posts.first.last[:data].map { |group| group[:id] }
  end

  def test_never_names_an_external_group_in_any_write
    @delivery.deliver(REQUEST)
    assert_empty((@client.posts + @client.patches).select { |write| write.to_s.include?('public') })
  end

  def test_makes_no_review_submission
    @delivery.deliver(REQUEST)
    assert_empty(@client.posts.select { |path, _body| path.include?('Submission') })
  end

  def test_stops_when_the_app_has_no_internal_group
    @client.groups = [@client.group('public', false, false)]
    error = assert_raises(DeliveryError) { @delivery.deliver(REQUEST) }
    assert_match(/no internal/, error.message)
    assert_empty @client.posts
  end

  def test_creates_the_note_when_the_build_has_none
    @delivery.deliver(REQUEST)
    created = @client.posts.find { |path, _body| path == '/v1/betaBuildLocalizations' }
    assert_equal 'Try it', created.last[:data][:attributes][:whatsNew]
  end

  def test_updates_an_existing_note
    @client.localizations = [{ 'id' => 'note', 'attributes' => { 'locale' => 'en-US' } }]
    @delivery.deliver(REQUEST)
    assert_equal '/v1/betaBuildLocalizations/note', @client.patches.first.first
  end

  def test_waits_for_processing_before_writing
    @client.processing_states = %w[PROCESSING PROCESSING VALID]
    @delivery.deliver(REQUEST)
    assert_equal 2, @naps.length
    assert_equal 1, group_posts.length
  end

  def test_stops_when_processing_fails
    @client.processing_states = ['INVALID']
    assert_raises(DeliveryError) { @delivery.deliver(REQUEST) }
    assert_empty @client.posts
  end

  def test_times_out_when_processing_never_finishes
    @client.processing_states = ['PROCESSING']
    error = assert_raises(DeliveryError) { @delivery.deliver(REQUEST) }
    assert_match(/timed out/, error.message)
  end

  def test_stops_on_missing_export_compliance
    @client.internal_state = 'MISSING_EXPORT_COMPLIANCE'
    error = assert_raises(DeliveryError) { @delivery.deliver(REQUEST) }
    assert_match(/MISSING_EXPORT_COMPLIANCE/, error.message)
  end
end
