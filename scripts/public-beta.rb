#!/usr/bin/env ruby
# frozen_string_literal: true

# Promotes an uploaded build, iPad and Mac together, to the app's external "Public beta" TestFlight group, and sends
# it to Beta App Review when Apple wants one. It never builds or uploads anything. Specified in
# docs/specs/release-train (R4). Run it from the app's checkout, which is asked whether the build has its tag.
#
# Usage: public-beta.rb <bundle-id> <build-number>
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE   the App Store Connect API key

require_relative 'train_store'

# Promotes one build number on every platform, or on none.
class PublicBetaPromotion
  GROUP = 'Public beta'
  ON_ORIGIN = lambda do |tag|
    system('git', 'ls-remote', '--exit-code', '--tags', 'origin', "refs/tags/#{tag}", out: File::NULL, err: File::NULL)
  end

  def initialize(client, store, tagged: ON_ORIGIN, log: ->(line) { puts line })
    @client = client
    @store = store
    @tagged = tagged
    @log = log
  end

  def promote(number)
    group_id = external_group
    builds = TrainStore::PLATFORMS.to_h { |platform| [platform, promotable_build(number, platform)] }
    builds.each do |platform, build|
      deliver(group_id, build.fetch('id'))
      @log.call("#{platform} build #{number}: #{@store.beta_states(build).fetch(:external)}")
    end
  end

  def self.run(arguments)
    bundle_id, number = arguments
    raise StoreError, 'usage: public-beta.rb <bundle-id> <build-number>' unless number

    client = AppStoreConnectClient.new(key_id: ENV.fetch('ASC_KEY_ID'), issuer_id: ENV.fetch('ASC_ISSUER_ID'),
                                       key_file: ENV.fetch('ASC_KEY_FILE'))
    new(client, TrainStore.new(client, bundle_id)).promote(number)
  end

  private

  def external_group
    groups = @client.get("/v1/apps/#{@store.app_id}/betaGroups", 'limit' => 200)
    group = groups.find do |candidate|
      candidate.dig('attributes', 'isInternalGroup') == false && candidate.dig('attributes', 'name') == GROUP
    end
    group&.fetch('id') || raise(StoreError, "the app has no external group named \"#{GROUP}\"")
  end

  # The platform's build, once it is processed, tagged in the repository and has a What to Test note.
  def promotable_build(number, platform)
    build = @store.processed_build(number, platform)
    tag = "testflight/#{@store.marketing_version(build)}-#{number}"
    raise StoreError, "#{platform} build #{number} has no #{tag} tag" unless @tagged.call(tag)
    raise StoreError, "#{platform} build #{number} has no What to Test note" unless note?(build)

    build
  end

  def note?(build)
    @client.get("/v1/builds/#{build.fetch('id')}/betaBuildLocalizations", 'limit' => 50)
           .any? { |localization| !localization.dig('attributes', 'whatsNew').to_s.strip.empty? }
  end

  # Apple forbids reading a build's groups, so the group's builds are read instead. A build is submitted only when
  # Apple says it is ready for that: one of a version it already approved goes to the testers at once.
  def deliver(group_id, build_id)
    in_group = @client.get("/v1/betaGroups/#{group_id}/builds", 'limit' => 200).any? { |build| build['id'] == build_id }
    builds = { data: [{ type: 'builds', id: build_id }] }
    @client.post("/v1/betaGroups/#{group_id}/relationships/builds", builds) unless in_group
    return unless @store.beta_states('id' => build_id).fetch(:external) == 'READY_FOR_BETA_SUBMISSION'

    @client.post('/v1/betaAppReviewSubmissions', data: {
                   type: 'betaAppReviewSubmissions',
                   relationships: { build: { data: { type: 'builds', id: build_id } } }
                 })
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    PublicBetaPromotion.run(ARGV)
  rescue AppStoreConnectError, KeyError, SystemCallError => e
    warn "public-beta: #{e.message}"
    exit 1
  end
end
