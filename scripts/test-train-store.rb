#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs train_store.rb against a stand-in for App Store Connect. Nothing is sent anywhere.

require 'minitest/autorun'
require_relative 'train_store'
require_relative 'train_test_support'

class TrainStoreTest < Minitest::Test
  def setup
    @client = FakeStoreClient.new
    @naps = []
    @store = TrainStore.new(@client, 'io.example.App', sleeper: ->(seconds) { @naps << seconds })
  end

  def answer(path, data)
    @client.answers[path] = data
  end

  def all_versions(state)
    answer('/v1/apps/app/appStoreVersions', ->(params) { [StoreAnswers.version(params['filter[platform]'], state)] })
  end

  def test_an_unknown_app_is_refused
    answer('/v1/apps', [])
    error = assert_raises(StoreError) { @store.app_id }
    assert_match(/no app io.example.App/, error.message)
  end

  def test_names_the_platforms_that_have_a_build
    answer('/v1/builds', ->(params) { params['filter[preReleaseVersion.platform]'] == 'IOS' ? [] : [{}] })
    assert_equal ['MAC_OS'], @store.platforms_with_build('12')
  end

  def test_a_missing_or_unprocessed_build_is_refused
    answer('/v1/builds', [])
    assert_match(/no build 12/, assert_raises(StoreError) { @store.processed_build('12', 'IOS') }.message)
    answer('/v1/builds', [StoreAnswers.build('IOS', 'PROCESSING')])
    assert_match(/PROCESSING/, assert_raises(StoreError) { @store.processed_build('12', 'IOS') }.message)
  end

  def test_reads_a_version_from_testflight
    assert_equal [12], @store.build_numbers('1.2.0', 'IOS')
    assert_equal({ build: '12', internal: 'IN_BETA_TESTING', external: 'READY_FOR_BETA_SUBMISSION' },
                 @store.testflight_state('1.2.0', 'IOS'))
    answer('/v1/builds', [])
    assert_equal '', @store.testflight_state('1.2.0', 'IOS').fetch(:build)
  end

  def test_reads_a_version_from_the_store
    assert_equal({ state: 'PREPARE_FOR_SUBMISSION', build: '12' }, @store.store_state('1.2.0', 'IOS'))
    answer('/v1/appStoreVersions/IOS-version/build', nil)
    assert_equal '', @store.store_state('1.2.0', 'IOS').fetch(:build)
    answer('/v1/apps/app/appStoreVersions', [])
    assert_equal 'NONE', @store.store_state('1.2.0', 'IOS').fetch(:state)
  end

  def test_an_older_record_gives_its_state_the_old_way
    assert_equal 'READY_FOR_SALE', TrainStore.state('attributes' => { 'appStoreState' => 'READY_FOR_SALE' })
  end

  def test_the_accepted_build_needs_both_platforms
    all_versions('PENDING_DEVELOPER_RELEASE')
    assert_equal '12', @store.accepted_build('1.2.0')
    answer('/v1/apps/app/appStoreVersions', lambda { |params|
      [StoreAnswers.version('IOS', params['filter[platform]'] == 'IOS' ? 'READY_FOR_SALE' : 'IN_REVIEW')]
    })
    assert_match(/MAC_OS 1.2.0 is IN_REVIEW/, assert_raises(StoreError) { @store.accepted_build('1.2.0') }.message)
  end

  def test_the_accepted_build_must_be_the_same_on_both
    all_versions('READY_FOR_SALE')
    answer('/v1/appStoreVersions/MAC_OS-version/build', { 'attributes' => { 'version' => '14' } })
    assert_match(/12 and 14/, assert_raises(StoreError) { @store.accepted_build('1.2.0') }.message)
  end

  def test_planning_a_submission_changes_nothing
    plans = @store.submission_plans('1.2.0', '12')
    assert_equal(%w[IOS MAC_OS], plans.map { |plan| plan.fetch(:platform) })
    assert_empty @client.writes
  end

  def test_a_build_of_another_version_is_refused
    answer('/v1/builds/MAC_OS-build/preReleaseVersion', { 'attributes' => { 'version' => '1.1.0' } })
    error = assert_raises(StoreError) { @store.submission_plans('1.2.0', '12') }
    assert_match(/MAC_OS build 12 is of version 1.1.0/, error.message)
  end

  def test_a_platform_in_review_is_refused
    answer('/v1/apps/app/reviewSubmissions', [{ 'id' => 'old', 'attributes' => { 'state' => 'UNRESOLVED_ISSUES' } }])
    error = assert_raises(StoreError) { @store.submission_plans('1.2.0', '12') }
    assert_match(/UNRESOLVED_ISSUES/, error.message)
  end

  def test_a_platform_without_a_version_to_edit_is_refused
    answer('/v1/apps/app/appStoreVersions', [])
    error = assert_raises(StoreError) { @store.submission_plans('1.2.0', '12') }
    assert_match(/push the listing first/, error.message)
  end

  def test_both_builds_are_attached_before_either_goes_to_review
    @store.submit(@store.submission_plans('1.2.0', '12'))
    assert_equal ['/v1/appStoreVersions/IOS-version', '/v1/appStoreVersions/MAC_OS-version', '/v1/reviewSubmissions'],
                 @client.paths.first(3)
    assert_equal 2, @client.paths(:patch).count('/v1/reviewSubmissions/new')
  end

  def test_the_version_is_named_and_released_by_hand
    @store.submit(@store.submission_plans('1.2.0', '12'))
    data = @client.writes.first.last.fetch(:data)
    assert_equal({ versionString: '1.2.0', releaseType: 'MANUAL' }, data.fetch(:attributes))
    assert_equal 'IOS-build', data.dig(:relationships, :build, :data, :id)
  end

  def test_the_submission_holds_the_version_and_is_sent
    @store.submit(@store.submission_plans('1.2.0', '12'))
    item = @client.writes.find { |write| write[1] == '/v1/reviewSubmissionItems' }.last
    assert_equal 'IOS-version', item.dig(:data, :relationships, :appStoreVersion, :data, :id)
    assert_equal({ submitted: true }, @client.writes.last.last.dig(:data, :attributes))
  end

  def test_an_unsent_submission_of_an_earlier_try_is_used_again
    drafts = ->(params) { params['filter[state]'] == 'READY_FOR_REVIEW' ? [{ 'id' => 'draft' }] : [] }
    answer('/v1/apps/app/reviewSubmissions', drafts)
    @store.submit(@store.submission_plans('1.2.0', '12').first(1))
    refute_includes @client.paths(:post), '/v1/reviewSubmissions'
    assert_includes @client.paths(:patch), '/v1/reviewSubmissions/draft'
  end

  def test_a_version_that_is_already_in_the_submission_is_not_added_twice
    item = { 'relationships' => { 'appStoreVersion' => { 'data' => { 'id' => 'IOS-version' } } } }
    answer(%r{\A/v1/reviewSubmissions/[^/]+/items\z}, [item])
    @store.submit(@store.submission_plans('1.2.0', '12').first(1))
    refute_includes @client.paths(:post), '/v1/reviewSubmissionItems'
  end

  def test_a_submission_holding_something_else_is_refused
    plans = @store.submission_plans('1.2.0', '12').first(1)
    answer(%r{\A/v1/reviewSubmissions/[^/]+/items\z}, [{ 'relationships' => {} }])
    error = assert_raises(StoreError) { @store.submit(plans) }
    assert_match(/something else/, error.message)
    refute_includes @client.paths(:patch), '/v1/reviewSubmissions/new'
  end

  def test_waits_for_the_version_to_be_ready_and_then_submits_anyway
    answer('/v1/appStoreVersions/IOS-version', StoreAnswers.version('IOS'))
    @store.submit(@store.submission_plans('1.2.0', '12').first(1))
    assert_equal TrainStore::READY_POLLS, @naps.length
    assert_includes @client.paths(:patch), '/v1/reviewSubmissions/new'
  end
end
