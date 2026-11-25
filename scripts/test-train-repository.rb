#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs train_repository.rb against a scratch repository with an origin, and train_github.rb against a stand-in for
# the gh command. Nothing leaves the machine.

require 'minitest/autorun'
require_relative 'train_github'
require_relative 'train_test_support'

class TrainRepositoryTest < Minitest::Test
  def setup
    @app = ScratchApp.new
    @repository = TrainRepository.new(@app.shell)
    @head = @app.git('rev-parse', 'HEAD')
  end

  def teardown
    @app.remove
  end

  def test_reads_the_version_build_number_and_bundle_identifier
    assert_equal '1.2.0', @repository.version('origin/main')
    assert_equal '1', @repository.build_number('origin/main')
    assert_equal 'io.example.App', @repository.bundle_id
  end

  def test_main_builds_until_a_version_is_in_review
    assert_equal 'main', @repository.train_branch
    @repository.create_branch('release/1.2.0', @head)
    assert_equal 'release/1.2.0', @repository.train_branch
    @repository.delete_branch('release/1.2.0')
    assert_empty @repository.release_branches
  end

  def test_two_versions_in_review_are_refused
    @repository.create_branch('release/1.2.0', @head)
    @repository.create_branch('release/1.3.0', @head)
    assert_raises(TrainError) { @repository.release_branches }
  end

  def test_a_tag_is_signed_and_pushed
    @repository.tag('testflight/1.2.0-1', @head, 'TestFlight build 1 of 1.2.0')
    assert @app.origin_has?('refs/tags/testflight/1.2.0-1')
    assert_includes @app.git('cat-file', 'tag', 'testflight/1.2.0-1'), 'BEGIN SSH SIGNATURE'
  end

  def test_tagging_again_is_harmless
    2.times { @repository.tag('testflight/1.2.0-1', @head, 'TestFlight build 1 of 1.2.0') }
    assert_equal @head, @repository.commit('refs/tags/testflight/1.2.0-1')
  end

  def test_a_tag_on_another_commit_is_left_alone
    @repository.tag('testflight/1.2.0-1', @head, 'first')
    newer = @app.write('file' => 'two')
    error = assert_raises(TrainError) { @repository.tag('testflight/1.2.0-1', newer, 'second') }
    assert_match(/another commit/, error.message)
  end

  def test_finds_uploaded_builds_by_their_tags
    @repository.tag('testflight/1.2.0-12', @head, 'twelve')
    @repository.tag('testflight/1.2.0-9', @head, 'nine')
    assert_equal [9, 12], @repository.tagged_builds('1.2.0')
    assert_equal '1.2.0', @repository.version_of_build('12')
    assert_raises(TrainError) { @repository.version_of_build('13') }
  end

  def test_a_missing_ref_is_named
    error = assert_raises(TrainError) { @repository.commit('refs/tags/v9.9.9') }
    assert_match(%r{no refs/tags/v9.9.9}, error.message)
  end

  def test_commits_on_a_branch_without_touching_the_checkout
    @repository.commit_on_branch(branch: 'chore/open-1.2.1', message: 'chore: Open version 1.2.1',
                                 files: { 'VERSION' => "1.2.1\n" })
    @repository.fetch
    assert_equal '1.2.1', @repository.version('origin/chore/open-1.2.1')
    assert_includes @app.git('cat-file', 'commit', 'origin/chore/open-1.2.1'), 'BEGIN SSH SIGNATURE'
    assert_equal "1.2.0\n", File.read(File.join(@app.dir, 'VERSION'))
    assert_equal 'main', @app.git('branch', '--show-current')
    assert_empty @app.git('branch', '--list', 'chore/*')
  end
end

# Answers gh from a list of [arguments it must include, output], and records what was run.
class FakeGh
  attr_reader :commands

  def initialize(answers)
    @answers = answers
    @commands = []
  end

  def run(*command)
    @commands << command
    answer = @answers.find { |words, _output| (words - command).empty? } || raise("unexpected #{command.join(' ')}")
    answer.last.respond_to?(:shift) ? answer.last.shift : answer.last
  end

  def ok?(*command)
    run(*command) == 'yes'
  end

  alias watch run
end

class TrainGitHubTest < Minitest::Test
  def github(answers)
    @gh = FakeGh.new(answers)
    @naps = []
    TrainGitHub.new(@gh, sleeper: ->(seconds) { @naps << seconds })
  end

  def test_a_dispatch_passes_the_inputs_and_reads_the_run_from_gh
    hub = github([[%w[run list], '7'], [%w[workflow run], 'https://github.com/o/r/actions/runs/42']])
    assert_equal '42', hub.dispatch('appstore.yml', 'main', upload: true, notes: 'Try it')
    assert_includes @gh.commands.last.join(' '), 'appstore.yml --ref main -f upload=true -f notes=Try it'
  end

  def test_an_older_gh_is_asked_for_the_new_run
    hub = github([[%w[run list], %w[7 7 8]], [%w[workflow run], '']])
    assert_equal '8', hub.dispatch('appstore.yml', 'main', {})
    assert_equal 1, @naps.length
  end

  def test_a_run_that_never_shows_stops_the_train
    hub = github([[%w[run list], '7'], [%w[workflow run], '']])
    assert_raises(TrainError) { hub.dispatch('appstore.yml', 'main', {}) }
  end

  def test_a_failed_run_stops_the_train
    shell = Shell.new
    error = assert_raises(TrainError) { shell.watch('false') }
    assert_match(/false failed/, error.message)
  end

  def test_reads_releases_pull_requests_and_runs
    hub = github([[%w[release view], 'yes'], [%w[pr list], "https://example.invalid/pull/3\n"],
                  [%w[run view], 'abc123'], [%w[repo view], 'https://github.com/o/r'], [%w[run watch], '']])
    assert hub.release?('v1.2.0')
    assert_equal ['https://example.invalid/pull/3'], hub.pull_requests('release/1.2.0')
    assert_equal 'abc123', hub.run_commit('42')
    assert_equal 'https://github.com/o/r', hub.url
    hub.watch('42')
    assert_equal %w[gh run watch 42 --exit-status], @gh.commands.last
  end

  def test_a_release_has_notes_and_no_files
    hub = github([[%w[release create], ''], [%w[pr create], 'https://example.invalid/pull/4']])
    hub.create_release('v1.2.0', 'Added dice')
    assert_equal %w[gh release create v1.2.0 --verify-tag --latest --title v1.2.0 --notes] + ['Added dice'],
                 @gh.commands.last
    hub.create_pull_request(branch: 'chore/open-1.2.1', title: 'chore: Open version 1.2.1', body: 'Next')
    assert_includes @gh.commands.last.join(' '), '--base main --head chore/open-1.2.1'
  end
end
