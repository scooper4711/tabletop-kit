# frozen_string_literal: true

# What `release-train.rb accept` does once Apple has accepted a version on both platforms. Specified in
# docs/specs/release-train (R5, R6).

require_relative 'changelog'
require_relative 'train_repository'

# Closes the accepted version and opens the next. Every step is skipped when it is already done.
class TrainAcceptance
  def initialize(repository:, github:, store:, log:, today:)
    @repository = repository
    @github = github
    @store = store
    @log = log
    @today = today
  end

  def accept
    @repository.fetch
    branches = @repository.release_branches
    version = branches.empty? ? @repository.version('origin/main') : branches.first.delete_prefix('release/')
    tag_accepted(version) unless @repository.tag?("v#{version}")
    publish_release(version)
    unmerged = branches.reject { |branch| @repository.ancestor?("origin/#{branch}", 'origin/main') }
    return unmerged.each { |branch| ask_for_merge(branch) } if unmerged.any?

    branches.each { |branch| @repository.delete_branch(branch) }
    open_next_version(version)
  end

  def self.next_patch(version)
    major, minor, patch = version.split('.').map(&:to_i)
    "#{major}.#{minor}.#{patch + 1}"
  end

  private

  def tag_accepted(version)
    build = @store.accepted_build(version)
    commit = @repository.commit("refs/tags/testflight/#{version}-#{build}")
    @repository.tag("v#{version}", commit, "Version #{version}: build #{build}, accepted by App Review")
    @log.call("v#{version} marks build #{build}, #{commit[0, 7]}")
  end

  def publish_release(version)
    return if @github.release?("v#{version}")

    notes = Changelog.new(@repository.file("refs/tags/v#{version}", 'CHANGELOG.md')).unreleased
    @github.create_release("v#{version}", notes)
  end

  # A fix made during review is on the release branch only, so main takes it through a pull request.
  def ask_for_merge(branch)
    body = 'Brings the fixes made during App Review back to `main`. After the merge, running `accept` again ' \
           'opens the next version.'
    url = @github.pull_requests(branch).first ||
          @github.create_pull_request(branch: branch, title: "chore: Merge #{branch} back into main", body: body)
    @log.call("Merge #{url}, then run accept again")
  end

  # VERSION moves to the next patch, and the changelog entries that shipped move under the accepted version.
  def open_next_version(version)
    return unless @repository.version('origin/main') == version

    following = TrainAcceptance.next_patch(version)
    branch = "chore/open-#{following}"
    url = @github.pull_requests(branch).first || propose_next_version(version, following, branch)
    @log.call("Version #{following} opens when this merges: #{url}")
  end

  def propose_next_version(version, following, branch)
    shipped = Changelog.new(@repository.file("refs/tags/v#{version}", 'CHANGELOG.md')).unreleased
    changelog = Changelog.new(@repository.file('origin/main', 'CHANGELOG.md')).release(
      version: version, date: @today.call.iso8601, shipped: shipped, link: "#{@github.url}/releases/tag/v#{version}"
    )
    @repository.commit_on_branch(branch: branch, message: "chore: Open version #{following}",
                                 files: { 'VERSION' => "#{following}\n", 'CHANGELOG.md' => changelog })
    @github.create_pull_request(branch: branch, title: "chore: Open version #{following}",
                                body: "Apple accepted #{version}, and `v#{version}` marks its build. `VERSION` now " \
                                      "names #{following}, and the changelog entries that shipped move under " \
                                      "#{version}. Raise `VERSION` further, before the first upload, if the next " \
                                      'release holds features.')
  end
end
