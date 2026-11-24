#!/usr/bin/env ruby
# frozen_string_literal: true

# Gives an uploaded build its What to Test note and delivers it to the app's internal TestFlight groups. It never adds
# a build to an external group or submits anything for review. Specified in docs/specs/app-store-pipeline.
#
# Usage: testflight-internal.rb <bundle-id> <build-number> <notes-file> <IOS,MAC_OS>
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE   the App Store Connect API key

require_relative 'app_store_connect_client'

class DeliveryError < AppStoreConnectError; end

# Delivers one build number, on each platform, to the internal groups.
class InternalTesterDelivery
  LOCALE = 'en-US'
  POLL_SECONDS = 30
  READY_STATES = %w[READY_FOR_BETA_TESTING IN_BETA_TESTING].freeze
  FAILED_BETA_STATES = %w[PROCESSING_EXCEPTION MISSING_EXPORT_COMPLIANCE EXPIRED].freeze

  def initialize(client, timeout_seconds: 3600, sleeper: ->(seconds) { sleep seconds }, log: ->(line) { puts line })
    @client = client
    @timeout_seconds = timeout_seconds
    @sleeper = sleeper
    @log = log
  end

  def deliver(request)
    app_id = find_app(request.fetch(:bundle_id))
    groups = internal_groups(app_id, request.fetch(:bundle_id))
    request.fetch(:platforms).each do |platform|
      build = wait_for_build(app_id, request.fetch(:build_number), platform)
      write_note(build.fetch('id'), request.fetch(:notes))
      add_to_groups(build.fetch('id'), groups)
      state = wait_for_internal_state(build.fetch('id'), platform)
      @log.call("#{request.fetch(:bundle_id)} #{platform} build #{request.fetch(:build_number)}: #{state}")
    end
  end

  private

  def find_app(bundle_id)
    apps = @client.get('/v1/apps', 'filter[bundleId]' => bundle_id, 'limit' => 200)
    app = apps.find { |candidate| candidate.dig('attributes', 'bundleId') == bundle_id }
    app&.fetch('id') || raise(DeliveryError, "App Store Connect has no app #{bundle_id}")
  end

  def internal_groups(app_id, bundle_id)
    groups = @client.get("/v1/apps/#{app_id}/betaGroups", 'limit' => 200)
    internal = groups.select { |group| group.dig('attributes', 'isInternalGroup') == true }
    raise DeliveryError, "#{bundle_id} has no internal TestFlight group" if internal.empty?

    internal
  end

  def wait_for_build(app_id, build_number, platform)
    poll("#{platform} build #{build_number} to finish processing") do
      build = find_build(app_id, build_number, platform)
      state = build&.dig('attributes', 'processingState')
      raise DeliveryError, "#{platform} build #{build_number} is #{state}" if %w[FAILED INVALID].include?(state)

      build if state == 'VALID'
    end
  end

  def find_build(app_id, build_number, platform)
    @client.get('/v1/builds', 'filter[app]' => app_id, 'filter[version]' => build_number.to_s,
                              'filter[preReleaseVersion.platform]' => platform, 'limit' => 1).first
  end

  def write_note(build_id, notes)
    existing = @client.get("/v1/builds/#{build_id}/betaBuildLocalizations", 'limit' => 50)
                      .find { |item| item.dig('attributes', 'locale') == LOCALE }
    return update_note(existing.fetch('id'), notes) if existing

    @client.post('/v1/betaBuildLocalizations', data: {
                   type: 'betaBuildLocalizations',
                   attributes: { locale: LOCALE, whatsNew: notes },
                   relationships: { build: { data: { type: 'builds', id: build_id } } }
                 })
  end

  def update_note(localization_id, notes)
    @client.patch("/v1/betaBuildLocalizations/#{localization_id}", data: {
                    type: 'betaBuildLocalizations', id: localization_id, attributes: { whatsNew: notes }
                  })
  end

  # Apple delivers every build to a group with access to all builds.
  def add_to_groups(build_id, groups)
    chosen = groups.reject { |group| group.dig('attributes', 'hasAccessToAllBuilds') == true }
    return if chosen.empty?

    data = chosen.map { |group| { type: 'betaGroups', id: group.fetch('id') } }
    @client.post("/v1/builds/#{build_id}/relationships/betaGroups", data: data)
  end

  def wait_for_internal_state(build_id, platform)
    poll("#{platform} build to be ready for internal testers") do
      detail = @client.get("/v1/builds/#{build_id}/buildBetaDetail")
      state = detail.dig('attributes', 'internalBuildState')
      raise DeliveryError, "#{platform} build's internal state is #{state}" if FAILED_BETA_STATES.include?(state)

      state if READY_STATES.include?(state)
    end
  end

  def poll(description)
    waited = 0
    loop do
      result = yield
      return result if result
      raise DeliveryError, "timed out waiting for #{description}" if waited >= @timeout_seconds

      @sleeper.call(POLL_SECONDS)
      waited += POLL_SECONDS
    end
  end
end

def run(arguments)
  bundle_id, build_number, notes_file, platforms = arguments
  raise DeliveryError, 'usage: testflight-internal.rb <bundle-id> <build> <notes-file> <IOS,MAC_OS>' unless platforms

  notes = File.read(notes_file).strip
  raise DeliveryError, 'the What to Test note is empty or over 4000 characters' unless notes.length.between?(1, 4000)

  client = AppStoreConnectClient.new(key_id: ENV.fetch('ASC_KEY_ID'), issuer_id: ENV.fetch('ASC_ISSUER_ID'),
                                     key_file: ENV.fetch('ASC_KEY_FILE'))
  InternalTesterDelivery.new(client).deliver(bundle_id: bundle_id, build_number: build_number, notes: notes,
                                             platforms: platforms.split(','))
end

if $PROGRAM_NAME == __FILE__
  begin
    run(ARGV)
  rescue AppStoreConnectError, KeyError, SystemCallError => e
    warn "testflight-internal: #{e.message}"
    exit 1
  end
end
