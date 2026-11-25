#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs release-train.rb's commands in a scratch repository with an origin, against stand-ins for GitHub and App Store
# Connect, and checks what docs/specs/release-train promises. Nothing leaves the machine.

require 'minitest/autorun'
require_relative 'release-train'
require_relative 'train_test_support'

# Stands in for TrainGitHub: records what was asked, and "runs" a workflow on the commit it is told to.
class FakeGitHub
  attr_reader :dispatches, :watched, :releases, :created
  attr_accessor :run_commit_answer, :open

  def initialize
    @dispatches = []
    @watched = []
    @releases = {}
    @created = []
    @open = {}
  end

  def url = 'https://github.com/example/app'
  def run_commit(_run) = @run_commit_answer
  def release?(tag) = @releases.key?(tag)
  def pull_requests(branch) = @open.fetch(branch, [])

  def dispatch(workflow, branch, inputs)
    @dispatches << [workflow, branch, inputs]
    '42'
  end

  def watch(run)
    @watched << run
  end

  def create_release(tag, notes)
    @releases[tag] = notes
  end

  def create_pull_request(branch:, title:, body:)
    @created << { branch: branch, title: title, body: body }
    "https://example.invalid/pull/#{@created.length}"
  end
end

# Stands in for TrainStore.
class FakeTrainStore
  attr_reader :submitted
  attr_accessor :uploaded, :accepted, :refusal, :numbers

  def initialize
    @uploaded = []
    @numbers = []
    @submitted = []
  end

  def platforms_with_build(_number) = @uploaded
  def build_numbers(_version, _platform) = @numbers
  def testflight_state(_version, _platform) = { build: '', internal: 'NONE', external: 'NONE' }
  def store_state(_version, _platform) = { state: 'IN_REVIEW', build: '1' }
  def accepted_build(_version) = @accepted || raise(StoreError, 'IOS 1.2.0 is IN_REVIEW, which is not accepted')

  def submission_plans(version, number)
    raise StoreError, @refusal if @refusal

    [[version, number]]
  end

  def submit(plans)
    @submitted.concat(plans)
  end
end

class ReleaseTrainTest < Minitest::Test
  def setup
    @app = ScratchApp.new
    @repository = TrainRepository.new(@app.shell)
    @github = FakeGitHub.new
    @store = FakeTrainStore.new
    @lines = []
    @head = @app.git('rev-parse', 'HEAD')
    @github.run_commit_answer = @head
    @train = ReleaseTrain.new(repository: @repository, github: @github, store: @store,
                              log: ->(line) { @lines << line }, today: -> { Date.new(2026, 2, 3) })
  end

  def teardown
    @app.remove
  end

  # Tags the first commit as uploaded build 1, as `upload` does.
  def uploaded
    @repository.tag('testflight/1.2.0-1', @head, 'TestFlight build 1 of 1.2.0')
  end

  # Build 1 is with App Review, and main has moved on.
  def in_review
    uploaded
    @train.submit('1')
    @app.write('CHANGELOG.md' => ScratchApp::CHANGELOG.sub("- Dice\n", "- Dice\n- Later\n"))
    @app.push
  end

  def refused(pattern, &)
    assert_match(pattern, assert_raises(TrainError, StoreError, &).message)
  end

  def test_upload_builds_main_and_tags_the_commit_the_run_built
    @train.upload
    assert_equal ['appstore.yml', 'main', { upload: true, internal_testers: true, notes: "Added:\n- Dice" }],
                 @github.dispatches.first
    assert_equal ['42'], @github.watched
    assert @app.origin_has?('refs/tags/testflight/1.2.0-1')
    assert_equal @head, @repository.commit('refs/tags/testflight/1.2.0-1')
  end

  def test_upload_tags_what_the_run_built_when_main_moved_meanwhile
    newer = @app.write('file' => 'two')
    @github.run_commit_answer = newer
    @app.git('update-ref', 'refs/remotes/origin/main', @head)
    @app.push
    @train.upload
    assert_equal newer, @repository.commit('refs/tags/testflight/1.2.0-2')
  end

  def test_upload_takes_a_note_in_place_of_the_changelog
    @train.upload('Check the dice')
    assert_equal 'Check the dice', @github.dispatches.first.last.fetch(:notes)
  end

  def test_upload_without_any_note_is_refused
    @app.write('CHANGELOG.md' => "# Changelog\n\n## [Unreleased]\n")
    @app.push
    refused(/nothing under Unreleased/) { @train.upload }
    refused(/over 4,000/) { @train.upload('x' * 4001) }
    assert_empty @github.dispatches
  end

  def test_upload_of_an_accepted_version_is_refused
    @repository.tag('v1.2.0', @head, 'accepted')
    refused(/1.2.0 is closed/) { @train.upload }
    assert_empty @github.dispatches
  end

  def test_upload_only_tags_a_build_apple_already_has
    @store.uploaded = ['MAC_OS']
    @train.upload
    assert_empty @github.dispatches
    assert @app.origin_has?('refs/tags/testflight/1.2.0-1')
  end

  def test_upload_builds_the_release_branch_while_a_version_is_in_review
    in_review
    @github.dispatches.clear
    fix = @app.git('rev-parse', 'origin/release/1.2.0')
    @github.run_commit_answer = fix
    @store.uploaded = ['IOS']
    @train.upload
    @store.uploaded = []
    @train.upload
    assert_equal 'release/1.2.0', @github.dispatches.first[1]
  end

  def test_beta_promotes_the_newest_tagged_build
    uploaded
    @repository.tag('testflight/1.2.0-7', @head, 'seven')
    @train.beta
    assert_equal [['public-beta.yml', 'main', { build: '7' }]], @github.dispatches
    assert_equal ['42'], @github.watched
  end

  def test_beta_takes_a_build_that_has_its_tag
    uploaded
    @train.beta('1')
    assert_equal({ build: '1' }, @github.dispatches.first.last)
    refused(/expected one/) { @train.beta('5') }
  end

  def test_beta_before_any_upload_is_refused
    refused(/no uploaded build yet/) { @train.beta }
    assert_empty @github.dispatches
  end

  def test_submit_cuts_the_release_branch_at_the_build_and_submits
    uploaded
    @app.write('file' => 'later')
    @app.push
    @train.submit('1')
    @repository.fetch
    assert_equal @head, @repository.commit('origin/release/1.2.0')
    assert_equal [['1.2.0', '1']], @store.submitted
  end

  def test_submit_leaves_no_branch_when_the_store_refuses
    uploaded
    @store.refusal = 'IOS has no version being prepared; push the listing first'
    refused(/push the listing/) { @train.submit('1') }
    refute @app.origin_has?('refs/heads/release/1.2.0')
  end

  def test_submit_refuses_an_untagged_or_accepted_build
    refused(/expected one/) { @train.submit('1') }
    uploaded
    @repository.tag('v1.2.0', @head, 'accepted')
    refused(/closed/) { @train.submit('1') }
    assert_empty @store.submitted
  end

  def test_submit_refuses_while_another_version_is_in_review
    uploaded
    @repository.create_branch('release/1.1.0', @head)
    refused(%r{release/1.1.0 is still in review}) { @train.submit('1') }
  end

  def test_a_fix_is_resubmitted_from_the_release_branch
    in_review
    @app.git('checkout', '--quiet', '--detach', 'origin/release/1.2.0')
    fix = @app.write('file' => 'fix')
    @app.push('release/1.2.0')
    @repository.tag('testflight/1.2.0-2', fix, 'TestFlight build 2 of 1.2.0')
    @train.submit('2')
    assert_equal [['1.2.0', '1'], ['1.2.0', '2']], @store.submitted
  end

  def test_a_build_from_main_is_refused_while_its_version_is_in_review
    in_review
    @repository.tag('testflight/1.2.0-2', @app.git('rev-parse', 'main'), 'from main')
    refused(%r{isn't on release/1.2.0}) { @train.submit('2') }
  end

  def test_accept_refuses_until_apple_accepted_both_platforms
    in_review
    refused(/not accepted/) { @train.accept }
    refute @repository.tag?('v1.2.0')
    assert_empty @github.releases
  end

  def test_accept_tags_the_accepted_build_and_writes_the_release
    in_review
    @store.accepted = '1'
    @train.accept
    assert @app.origin_has?('refs/tags/v1.2.0')
    assert_equal @head, @repository.commit('refs/tags/v1.2.0')
    assert_equal({ 'v1.2.0' => "### Added\n- Dice" }, @github.releases)
  end

  def test_accept_deletes_the_branch_and_proposes_the_next_version
    in_review
    @store.accepted = '1'
    @train.accept
    @repository.fetch
    assert_empty @repository.release_branches
    assert_equal ['chore: Open version 1.2.1'], @github.created.map { |request| request.fetch(:title) }
    assert_equal '1.2.1', @repository.version('origin/chore/open-1.2.1')
  end

  def test_the_next_version_splits_the_changelog_at_the_tag
    in_review
    @store.accepted = '1'
    @train.accept
    @repository.fetch
    changelog = @repository.file('origin/chore/open-1.2.1', 'CHANGELOG.md')
    assert_includes changelog, "## [Unreleased]\n\n### Added\n- Later\n\n## [1.2.0] - 2026-02-03\n\n### Added\n- Dice\n"
    assert_includes changelog, '[1.2.0]: https://github.com/example/app/releases/tag/v1.2.0'
  end

  def test_accept_asks_for_a_merge_when_the_branch_holds_a_fix
    in_review
    @app.git('checkout', '--quiet', '--detach', 'origin/release/1.2.0')
    fix = @app.write('file' => 'fix')
    @app.push('release/1.2.0')
    @repository.tag('testflight/1.2.0-2', fix, 'TestFlight build 2 of 1.2.0')
    @store.accepted = '2'
    @train.accept
    assert_equal fix, @repository.commit('refs/tags/v1.2.0')
    assert_equal ['release/1.2.0'], @github.created.map { |request| request.fetch(:branch) }
    assert @app.origin_has?('refs/heads/release/1.2.0')
    assert_match(/Merge .* then run accept again/, @lines.last)
  end

  def test_accept_again_changes_nothing_that_is_done
    in_review
    @store.accepted = '1'
    @train.accept
    @github.open['chore/open-1.2.1'] = ['https://example.invalid/pull/1']
    @store.accepted = nil
    @train.accept
    assert_equal 1, @github.created.length
    assert_equal 1, @github.releases.length
  end

  def test_accept_is_finished_once_the_next_version_is_on_main
    in_review
    @repository.tag('v1.2.0', @head, 'accepted')
    @github.releases['v1.2.0'] = 'notes'
    @repository.delete_branch('release/1.2.0')
    @app.write('VERSION' => "1.2.1\n")
    @app.push
    refused(/not accepted/) { @train.accept }
    assert_empty @github.created
  end

  def test_status_names_the_position_each_platform_and_untagged_uploads
    uploaded
    @store.numbers = [1, 3]
    @train.status
    assert_equal 'Version 1.2.0: open on main', @lines.first
    assert_equal 'IOS: TestFlight no build; App Store IN_REVIEW, build 1', @lines[1]
    assert_equal 'Uploads without a tag: 3', @lines.last
  end

  def test_status_says_when_a_version_is_in_review_or_closed
    in_review
    @lines.clear
    @train.status
    assert_match(%r{in review on release/1.2.0}, @lines.first)
    @repository.tag('v1.2.0', @head, 'accepted')
    @train.status
    assert_includes @lines.join("\n"), 'closed, v1.2.0 is accepted'
  end

  def test_the_command_refuses_what_it_does_not_know
    refused(/usage/) { ReleaseTrain.run(['launch']) }
    refused(/usage/) { ReleaseTrain.run(['submit']) }
    assert_equal '1.2.1', TrainAcceptance.next_patch('1.2.0')
  end
end
