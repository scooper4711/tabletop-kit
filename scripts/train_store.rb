# frozen_string_literal: true

# What release-train.rb and public-beta.rb read from, and change in, an app's App Store Connect record.
# Specified in docs/specs/release-train.

require_relative 'app_store_connect_client'

class StoreError < AppStoreConnectError; end

# One app in App Store Connect: its builds, its App Store versions and its submissions to App Review.
class TrainStore
  PLATFORMS = %w[IOS MAC_OS].freeze
  EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
  ACCEPTED = %w[PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE PROCESSING_FOR_DISTRIBUTION READY_FOR_DISTRIBUTION
                READY_FOR_SALE].freeze
  IN_REVIEW = %w[WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES].freeze
  READY_POLLS = 10
  READY_POLL_SECONDS = 15

  def initialize(client, bundle_id, sleeper: ->(seconds) { sleep seconds })
    @client = client
    @bundle_id = bundle_id
    @sleeper = sleeper
  end

  def app_id
    @app_id ||= begin
      apps = @client.get('/v1/apps', 'filter[bundleId]' => @bundle_id, 'limit' => 200)
      app = apps.find { |candidate| candidate.dig('attributes', 'bundleId') == @bundle_id }
      app&.fetch('id') || raise(StoreError, "App Store Connect has no app #{@bundle_id}")
    end
  end

  # The platforms that have a build with this number.
  def platforms_with_build(number)
    PLATFORMS.select { |platform| find_builds(platform, 'filter[version]' => number.to_s).any? }
  end

  # A platform's processed build with this number. Stops when there is none, or Apple hasn't finished with it.
  def processed_build(number, platform)
    build = find_builds(platform, 'filter[version]' => number.to_s).first
    raise StoreError, "#{platform} has no build #{number}" unless build

    state = build.dig('attributes', 'processingState')
    raise StoreError, "#{platform} build #{number} is #{state}, not processed" unless state == 'VALID'

    build
  end

  # A platform's build numbers for a version, newest upload first.
  def build_numbers(version, platform)
    uploads(version, platform).map { |build| build.dig('attributes', 'version').to_i }
  end

  def marketing_version(build)
    @client.get("/v1/builds/#{build.fetch('id')}/preReleaseVersion").dig('attributes', 'version')
  end

  # The TestFlight states of a platform's newest upload of a version, as { build:, internal:, external: }. Without
  # an upload, the build is empty.
  def testflight_state(version, platform)
    newest = uploads(version, platform).first
    return { build: '', internal: 'NONE', external: 'NONE' } unless newest

    beta_states(newest).merge(build: newest.dig('attributes', 'version'))
  end

  # A build's TestFlight states, as { internal:, external: }.
  def beta_states(build)
    detail = @client.get("/v1/builds/#{build.fetch('id')}/buildBetaDetail").fetch('attributes')
    { internal: detail['internalBuildState'], external: detail['externalBuildState'] }
  end

  # A platform's App Store record of a version, as { state:, build: }. Without a record, the state is NONE.
  def store_state(version, platform)
    record = @client.get("/v1/apps/#{app_id}/appStoreVersions", 'filter[versionString]' => version,
                                                                'filter[platform]' => platform, 'limit' => 1).first
    return { state: 'NONE', build: '' } unless record

    build = @client.get("/v1/appStoreVersions/#{record.fetch('id')}/build")
    { state: TrainStore.state(record), build: build ? build.dig('attributes', 'version').to_s : '' }
  end

  # The build number Apple accepted for the version. Stops unless both platforms are accepted with the same build.
  def accepted_build(version)
    builds = PLATFORMS.map do |platform|
      record = store_state(version, platform)
      next record.fetch(:build) if ACCEPTED.include?(record.fetch(:state))

      raise StoreError, "#{platform} #{version} is #{record.fetch(:state)}, which is not accepted"
    end
    raise StoreError, "the platforms were accepted with builds #{builds.join(' and ')}" if builds.uniq.length > 1

    builds.first
  end

  # What sending the build to App Review needs, per platform. Stops unless both platforms can go; changes nothing.
  def submission_plans(version, number)
    PLATFORMS.map { |platform| submission_plan(version, number, platform) }
  end

  # Attaches each plan's build and sets the release by hand, then sends both platforms to App Review. The builds go
  # on first, so a platform that refuses its build stops the other from going to review alone.
  def submit(plans)
    plans.each { |plan| attach(plan) }
    plans.each { |plan| send_to_review(plan) }
  end

  def self.state(version_record)
    version_record.dig('attributes', 'appVersionState') || version_record.dig('attributes', 'appStoreState')
  end

  private

  def uploads(version, platform)
    find_builds(platform, 'filter[preReleaseVersion.version]' => version, 'sort' => '-uploadedDate')
  end

  def find_builds(platform, filters)
    @client.get('/v1/builds', { 'filter[app]' => app_id, 'filter[preReleaseVersion.platform]' => platform,
                                'limit' => 200 }.merge(filters))
  end

  def submissions(platform, states)
    @client.get("/v1/apps/#{app_id}/reviewSubmissions", 'filter[platform]' => platform,
                                                        'filter[state]' => states.join(','))
  end

  def submission_plan(version, number, platform)
    build = processed_build(number, platform)
    uploaded_as = marketing_version(build)
    raise StoreError, "#{platform} build #{number} is of version #{uploaded_as}" if uploaded_as != version

    open = submissions(platform, IN_REVIEW).first
    raise StoreError, "#{platform} already has a submission that is #{open.dig('attributes', 'state')}" if open

    { platform: platform, version: version, build_id: build.fetch('id'), record_id: editable_record(platform) }
  end

  # The App Store version that can still be changed. The store listing push makes it and names it.
  def editable_record(platform)
    records = @client.get("/v1/apps/#{app_id}/appStoreVersions", 'filter[platform]' => platform,
                                                                 'filter[appVersionState]' => EDITABLE.join(','))
    records.first&.fetch('id') || raise(StoreError, "#{platform} has no version being prepared; push the listing first")
  end

  def attach(plan)
    @client.patch("/v1/appStoreVersions/#{plan.fetch(:record_id)}", data: {
                    type: 'appStoreVersions', id: plan.fetch(:record_id),
                    attributes: { versionString: plan.fetch(:version), releaseType: 'MANUAL' },
                    relationships: { build: { data: { type: 'builds', id: plan.fetch(:build_id) } } }
                  })
  end

  def send_to_review(plan)
    submission_id = draft_submission(plan.fetch(:platform))
    add_version(submission_id, plan.fetch(:record_id))
    wait_until_ready(plan.fetch(:record_id))
    @client.patch("/v1/reviewSubmissions/#{submission_id}", data: {
                    type: 'reviewSubmissions', id: submission_id, attributes: { submitted: true }
                  })
  end

  # An app has one unsent submission per platform at most: an earlier try's is used again.
  def draft_submission(platform)
    draft = submissions(platform, ['READY_FOR_REVIEW']).first
    return draft.fetch('id') if draft

    @client.post('/v1/reviewSubmissions', data: {
                   type: 'reviewSubmissions', attributes: { platform: platform },
                   relationships: { app: { data: { type: 'apps', id: app_id } } }
                 }).dig('data', 'id')
  end

  def add_version(submission_id, record_id)
    items = @client.get("/v1/reviewSubmissions/#{submission_id}/items", 'include' => 'appStoreVersion')
    versions = items.map { |item| item.dig('relationships', 'appStoreVersion', 'data', 'id') }
    return if versions == [record_id]
    raise StoreError, 'the unsent submission holds something else; clear it in App Store Connect' unless items.empty?

    @client.post('/v1/reviewSubmissionItems', data: {
                   type: 'reviewSubmissionItems',
                   relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: submission_id } },
                                    appStoreVersion: { data: { type: 'appStoreVersions', id: record_id } } }
                 })
  end

  # App Store Connect takes a moment to accept the item. After the wait, submitting says what is wrong, if anything.
  def wait_until_ready(record_id)
    READY_POLLS.times do
      return if TrainStore.state(@client.get("/v1/appStoreVersions/#{record_id}")) == 'READY_FOR_REVIEW'

      @sleeper.call(READY_POLL_SECONDS)
    end
  end
end
