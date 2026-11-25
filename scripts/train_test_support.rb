# frozen_string_literal: true

# Shared by the release train's tests: a made-up app repository with an origin, and a stand-in for App Store Connect.

require 'fileutils'
require 'tmpdir'
require_relative 'train_repository'

# An app's checkout and its origin, in a scratch folder. Tags and commits are signed with a key made for the test,
# so nothing reads the keychain.
class ScratchApp
  WORKFLOW = "jobs:\n  package:\n    env:\n      BUNDLE_ID: io.example.App\n"
  CHANGELOG = "# Changelog\n\n## [Unreleased]\n\n### Added\n- Dice\n\n## [1.1.0] - 2026-01-01\n\n### Fixed\n- Old\n"

  attr_reader :dir, :shell

  def initialize
    @root = Dir.mktmpdir('train-test')
    @dir = File.join(@root, 'app')
    [['--bare', File.join(@root, 'origin.git')], [@dir]].each do |where|
      system('git', 'init', '--quiet', '--initial-branch', 'main', *where, exception: true)
    end
    @shell = Shell.new(@dir)
    configure
    write('VERSION' => "1.2.0\n", 'CHANGELOG.md' => CHANGELOG, '.github/workflows/appstore.yml' => WORKFLOW)
    git('remote', 'add', 'origin', File.join(@root, 'origin.git'))
    push
  end

  def remove
    FileUtils.rm_rf(@root)
  end

  def git(*arguments)
    @shell.run('git', *arguments)
  end

  # Commits the files (path => text) on the checked-out branch and gives the commit.
  def write(files)
    files.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(@dir, path)))
      File.write(File.join(@dir, path), text)
    end
    git('add', '--all')
    git('commit', '--quiet', '-m', "Change #{files.keys.join(', ')}")
    git('rev-parse', 'HEAD')
  end

  def push(branch = 'main')
    git('push', '--quiet', 'origin', "HEAD:refs/heads/#{branch}")
  end

  def origin_has?(ref)
    !git('ls-remote', 'origin', ref).empty?
  end

  private

  def configure
    key = File.join(@root, 'key')
    system('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', key, exception: true)
    { 'user.name' => 'Test', 'user.email' => 'test@example.invalid', 'gpg.format' => 'ssh',
      'user.signingkey' => "#{key}.pub", 'commit.gpgsign' => 'false', 'tag.gpgsign' => 'false' }
      .each { |name, value| git('config', name, value) }
  end
end

# Answers like App Store Connect from a table of paths, and records every write.
class FakeStoreClient
  attr_reader :writes, :answers

  def initialize(answers = StoreAnswers.healthy)
    @answers = answers
    @writes = []
  end

  # An answer is the data itself, or a block that gets the request's parameters. A path can be a pattern.
  def get(path, params = {})
    key = @answers.keys.find { |candidate| candidate == path || (candidate.is_a?(Regexp) && candidate.match?(path)) }
    raise "unexpected GET #{path}" unless key

    answer = @answers.fetch(key)
    answer.respond_to?(:call) ? answer.call(params) : answer
  end

  def post(path, body)
    @writes << [:post, path, body]
    { 'data' => { 'id' => 'new' } }
  end

  def patch(path, body)
    @writes << [:patch, path, body]
    {}
  end

  def paths(method = nil)
    @writes.select { |write| method.nil? || write.first == method }.map { |write| write[1] }
  end
end

# What App Store Connect says about an app whose build 12 of version 1.2.0 is processed on both platforms, has a
# What to Test note and isn't with any review. Tests change single answers.
module StoreAnswers
  def self.healthy
    answers = app_answers
    %w[IOS MAC_OS].each { |platform| answers.merge!(build_answers(platform), version_answers(platform)) }
    answers
  end

  def self.app_answers
    {
      '/v1/apps' => [{ 'id' => 'app', 'attributes' => { 'bundleId' => 'io.example.App' } }],
      '/v1/builds' => ->(params) { [build(params.fetch('filter[preReleaseVersion.platform]'))] },
      '/v1/apps/app/appStoreVersions' => ->(params) { [version(params.fetch('filter[platform]'))] },
      '/v1/apps/app/reviewSubmissions' => [],
      '/v1/apps/app/betaGroups' => [group('team', true), group('public', false)],
      '/v1/betaGroups/public/builds' => [],
      %r{\A/v1/reviewSubmissions/[^/]+/items\z} => []
    }
  end

  def self.build_answers(platform)
    {
      "/v1/builds/#{platform}-build/preReleaseVersion" => { 'attributes' => { 'version' => '1.2.0' } },
      "/v1/builds/#{platform}-build/betaBuildLocalizations" => [{ 'attributes' => { 'whatsNew' => 'Try it' } }],
      "/v1/builds/#{platform}-build/buildBetaDetail" => { 'attributes' => {
        'internalBuildState' => 'IN_BETA_TESTING', 'externalBuildState' => 'READY_FOR_BETA_SUBMISSION'
      } }
    }
  end

  def self.version_answers(platform)
    {
      "/v1/appStoreVersions/#{platform}-version" => version(platform, 'READY_FOR_REVIEW'),
      "/v1/appStoreVersions/#{platform}-version/build" => { 'attributes' => { 'version' => '12' } }
    }
  end

  def self.build(platform, state = 'VALID')
    { 'id' => "#{platform}-build", 'attributes' => { 'version' => '12', 'processingState' => state } }
  end

  def self.version(platform, state = 'PREPARE_FOR_SUBMISSION')
    { 'id' => "#{platform}-version", 'attributes' => { 'versionString' => '1.2.0', 'appVersionState' => state } }
  end

  def self.group(id, internal)
    { 'id' => id, 'attributes' => { 'isInternalGroup' => internal, 'name' => internal ? 'Team' : 'Public beta' } }
  end
end
