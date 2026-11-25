#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs public-beta.rb's promotion against a stand-in for App Store Connect. Nothing is sent anywhere.

require 'minitest/autorun'
require_relative 'public-beta'
require_relative 'train_test_support'

class PublicBetaPromotionTest < Minitest::Test
  GROUP_BUILDS = '/v1/betaGroups/public/relationships/builds'
  REVIEW = '/v1/betaAppReviewSubmissions'

  def setup
    @client = FakeStoreClient.new
    @tags = ['testflight/1.2.0-12']
    @lines = []
    store = TrainStore.new(@client, 'io.example.App')
    @promotion = PublicBetaPromotion.new(@client, store, tagged: ->(tag) { @tags.include?(tag) },
                                                         log: ->(line) { @lines << line })
  end

  def refused(pattern)
    error = assert_raises(StoreError) { @promotion.promote('12') }
    assert_match(pattern, error.message)
    assert_empty @client.writes
  end

  def test_both_platforms_join_the_external_group_and_go_to_beta_review
    @promotion.promote('12')
    assert_equal [GROUP_BUILDS, REVIEW, GROUP_BUILDS, REVIEW], @client.paths
    reviewed = @client.writes.select { |write| write[1] == REVIEW }
    assert_equal(%w[IOS-build MAC_OS-build],
                 reviewed.map { |write| write.last.dig(:data, :relationships, :build, :data, :id) })
    assert_equal ['IOS build 12: READY_FOR_BETA_SUBMISSION', 'MAC_OS build 12: READY_FOR_BETA_SUBMISSION'], @lines
  end

  def test_the_internal_group_is_never_written_to
    @promotion.promote('12')
    assert_empty(@client.paths.select { |path| path.include?('team') })
  end

  def test_a_build_already_in_the_group_is_not_added_again
    @client.answers['/v1/betaGroups/public/builds'] = [{ 'id' => 'IOS-build' }]
    @promotion.promote('12')
    assert_equal 1, @client.paths.count(GROUP_BUILDS)
  end

  def test_a_build_of_an_approved_version_needs_no_review
    %w[IOS MAC_OS].each do |platform|
      @client.answers["/v1/builds/#{platform}-build/buildBetaDetail"] =
        { 'attributes' => { 'externalBuildState' => 'IN_BETA_TESTING' } }
    end
    @promotion.promote('12')
    assert_equal [GROUP_BUILDS, GROUP_BUILDS], @client.paths
  end

  def test_an_untagged_build_is_refused
    @tags.clear
    refused(%r{no testflight/1.2.0-12 tag})
  end

  def test_a_build_without_a_note_on_one_platform_stops_both
    @client.answers['/v1/builds/MAC_OS-build/betaBuildLocalizations'] = [{ 'attributes' => { 'whatsNew' => ' ' } }]
    refused(/MAC_OS build 12 has no What to Test note/)
  end

  def test_an_unprocessed_build_is_refused
    @client.answers['/v1/builds'] = [StoreAnswers.build('IOS', 'PROCESSING')]
    refused(/PROCESSING/)
  end

  def test_an_app_without_the_external_group_is_refused
    @client.answers['/v1/apps/app/betaGroups'] = [StoreAnswers.group('team', true)]
    refused(/no external group named "Public beta"/)
  end

  def test_the_command_wants_a_bundle_identifier_and_a_build
    assert_match(/usage/, assert_raises(StoreError) { PublicBetaPromotion.run(['io.example.App']) }.message)
  end

  def test_the_tag_is_looked_up_on_origin
    app = ScratchApp.new
    TrainRepository.new(app.shell).tag('testflight/1.2.0-12', app.git('rev-parse', 'HEAD'), 'twelve')
    app.git('tag', '--delete', 'testflight/1.2.0-12')
    Dir.chdir(app.dir) do
      assert PublicBetaPromotion::ON_ORIGIN.call('testflight/1.2.0-12')
      refute PublicBetaPromotion::ON_ORIGIN.call('testflight/1.2.0-13')
    end
  ensure
    app.remove
  end
end
