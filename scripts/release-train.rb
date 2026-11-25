#!/usr/bin/env ruby
# frozen_string_literal: true

# Moves an App Store app along its release train: VERSION names the version being worked toward, every upload gets a
# testflight/<version>-<build> tag, and v<version> marks the build Apple accepted. Specified in
# docs/specs/release-train. Run it from the app's checkout; it never changes the working tree.
#
# Usage: release-train.rb status           where the version stands, in git and in App Store Connect
#        release-train.rb upload [note]    build in CI, deliver to the internal testers, tag the commit
#        release-train.rb beta [build]     promote an uploaded build to the Public beta group (default: the newest)
#        release-train.rb submit <build>   cut release/<version> at the build and send both platforms to App Review
#        release-train.rb accept           once Apple accepted: tag v<version>, write the release, open the next version
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE   the App Store Connect API key

require 'date'
require_relative 'changelog'
require_relative 'train_acceptance'
require_relative 'train_github'
require_relative 'train_repository'
require_relative 'train_store'

# One app's train. Each command is safe to run again after it stopped halfway.
class ReleaseTrain
  USAGE = 'usage: release-train.rb status | upload [note] | beta [build] | submit <build> | accept'
  ARGUMENTS = { 'status' => 0..0, 'upload' => 0..1, 'beta' => 0..1, 'submit' => 1..1, 'accept' => 0..0 }.freeze

  def initialize(repository:, github:, store:, log: ->(line) { puts line }, today: -> { Date.today })
    @repository = repository
    @github = github
    @store = store
    @log = log
    @acceptance = TrainAcceptance.new(repository: repository, github: github, store: store, log: log, today: today)
  end

  def status
    @repository.fetch
    branch = @repository.train_branch
    version = @repository.version("origin/#{branch}")
    @log.call("Version #{version}: #{position(version, branch)}")
    TrainStore::PLATFORMS.each { |platform| @log.call(platform_status(version, platform)) }
    uploads = TrainStore::PLATFORMS.flat_map { |platform| @store.build_numbers(version, platform) }.uniq.sort
    untagged = uploads - @repository.tagged_builds(version)
    @log.call("Uploads without a tag: #{untagged.join(', ')}") if untagged.any?
  end

  def upload(note = '')
    @repository.fetch
    branch = @repository.train_branch
    commit = @repository.commit("origin/#{branch}")
    refuse_closed(@repository.version(commit))
    # A build that is already at Apple's is only tagged: this is the second run after a failed tag.
    commit = build_in_ci(branch, commit, note) if @store.platforms_with_build(@repository.build_number(commit)).empty?
    tag_upload(commit)
  end

  def beta(build = '')
    @repository.fetch
    build = newest_tagged_build if build.empty?
    @repository.version_of_build(build)
    @github.watch(@github.dispatch('public-beta.yml', 'main', build: build))
  end

  def submit(build)
    @repository.fetch
    version = @repository.version_of_build(build)
    refuse_closed(version)
    commit = @repository.commit("refs/tags/testflight/#{version}-#{build}")
    in_review = @repository.release_branches
    refuse_another_review(in_review, version, commit)
    plans = @store.submission_plans(version, build)
    @repository.create_branch("release/#{version}", commit) if in_review.empty?
    @store.submit(plans)
    @log.call("#{version} build #{build} is with App Review on both platforms; release/#{version} is frozen")
  end

  def accept
    @acceptance.accept
  end

  # Runs one command line, in the checkout the command was started from.
  def self.run(arguments)
    command, *rest = arguments
    raise TrainError, USAGE unless ARGUMENTS[command]&.cover?(rest.length)

    shell = Shell.new
    repository = TrainRepository.new(shell)
    client = AppStoreConnectClient.new(key_id: ENV.fetch('ASC_KEY_ID'), issuer_id: ENV.fetch('ASC_ISSUER_ID'),
                                       key_file: ENV.fetch('ASC_KEY_FILE'))
    new(repository: repository, github: TrainGitHub.new(shell), store: TrainStore.new(client, repository.bundle_id))
      .public_send(command, *rest)
  end

  private

  def position(version, branch)
    return "closed, v#{version} is accepted; raise VERSION to open the next" if @repository.tag?("v#{version}")

    branch == 'main' ? 'open on main' : "in review on #{branch}; main may not upload"
  end

  def platform_status(version, platform)
    beta = @store.testflight_state(version, platform)
    store = @store.store_state(version, platform)
    testflight = "build #{beta.fetch(:build)}, internal #{beta.fetch(:internal)}, external #{beta.fetch(:external)}"
    testflight = 'no build' if beta.fetch(:build).empty?
    attached = store.fetch(:build).empty? ? 'no build' : "build #{store.fetch(:build)}"
    "#{platform}: TestFlight #{testflight}; App Store #{store.fetch(:state)}, #{attached}"
  end

  def refuse_closed(version)
    return unless @repository.tag?("v#{version}")

    raise TrainError, "version #{version} is closed: v#{version} marks the accepted build, so raise VERSION first"
  end

  # Starts appstore.yml on the branch and gives the commit it built.
  def build_in_ci(branch, commit, note)
    note = Changelog.new(@repository.file(commit, 'CHANGELOG.md')).note if note.empty?
    raise TrainError, 'CHANGELOG.md has nothing under Unreleased; pass a What to Test note' if note.empty?
    raise TrainError, 'the What to Test note is over 4,000 characters' if note.length > Changelog::NOTE_LIMIT

    run = @github.dispatch('appstore.yml', branch, upload: true, internal_testers: true, notes: note)
    @github.watch(run)
    @repository.fetch
    @github.run_commit(run)
  end

  def tag_upload(commit)
    version = @repository.version(commit)
    build = @repository.build_number(commit)
    @repository.tag("testflight/#{version}-#{build}", commit, "TestFlight build #{build} of #{version}")
    @log.call("testflight/#{version}-#{build} marks #{commit[0, 7]}")
  end

  def newest_tagged_build
    version = @repository.version("origin/#{@repository.train_branch}")
    builds = @repository.tagged_builds(version)
    raise TrainError, "version #{version} has no uploaded build yet" if builds.empty?

    builds.last.to_s
  end

  # One version is with App Review at a time, and a resubmitted build comes from its branch.
  def refuse_another_review(in_review, version, commit)
    return if in_review.empty?
    raise TrainError, "#{in_review.first} is still in review" unless in_review == ["release/#{version}"]
    return if @repository.ancestor?(commit, "origin/#{in_review.first}")

    raise TrainError, "that build isn't on #{in_review.first}, which is in review"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    ReleaseTrain.run(ARGV)
  rescue TrainError, ChangelogError, AppStoreConnectError, KeyError, SystemCallError => e
    warn "release-train: #{e.message}"
    exit 1
  end
end
