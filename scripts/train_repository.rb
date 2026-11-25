# frozen_string_literal: true

# What release-train.rb reads from, and writes to, an app's git repository. Specified in docs/specs/release-train.

require 'open3'
require 'tmpdir'

class TrainError < StandardError; end

# Runs commands in one folder.
class Shell
  def initialize(dir = Dir.pwd)
    @dir = dir
  end

  # The command's output. A command that fails stops the train with what it said.
  def run(*command)
    output, error, status = Open3.capture3(*command, chdir: @dir)
    raise TrainError, "#{command.first(3).join(' ')} failed: #{error.strip[0, 500]}" unless status.success?

    output.strip
  end

  def ok?(*command)
    Open3.capture3(*command, chdir: @dir).last.success?
  end

  # Runs the command on the terminal, for one that reports its own progress.
  def watch(*command)
    system(*command, chdir: @dir) || raise(TrainError, "#{command.first(3).join(' ')} failed")
  end

  def in(dir)
    Shell.new(dir)
  end
end

# An app's checkout. It reads origin's branches and tags, and never touches the working tree.
class TrainRepository
  def initialize(shell)
    @shell = shell
  end

  def fetch
    @shell.run('git', 'fetch', '--quiet', '--prune', '--tags', 'origin')
  end

  # The branches of versions that are with App Review: none, or one.
  def release_branches
    names = @shell.run('git', 'for-each-ref', '--format=%(refname:lstrip=3)', 'refs/remotes/origin/release').split
    raise TrainError, "more than one version is in review: #{names.join(', ')}" if names.length > 1

    names
  end

  # The branch that builds are made from: a version's release branch while it is in review, otherwise main.
  def train_branch
    release_branches.first || 'main'
  end

  def commit(ref)
    @shell.run('git', 'rev-parse', '--verify', '--quiet', "#{ref}^{commit}")
  rescue TrainError
    raise TrainError, "the repository has no #{ref}"
  end

  def file(commit, path)
    @shell.run('git', 'show', "#{commit}:#{path}")
  end

  def version(commit)
    file(commit, 'VERSION').strip
  end

  def build_number(commit)
    @shell.run('git', 'rev-list', '--count', commit)
  end

  def bundle_id
    workflow = file('origin/main', '.github/workflows/appstore.yml')
    workflow[/^\s*BUNDLE_ID:\s*(\S+)/, 1] || raise(TrainError, 'appstore.yml names no BUNDLE_ID')
  end

  def tag?(name)
    @shell.ok?('git', 'rev-parse', '--verify', '--quiet', "refs/tags/#{name}^{commit}")
  end

  def ancestor?(commit, descendant)
    @shell.ok?('git', 'merge-base', '--is-ancestor', commit, descendant)
  end

  # The build numbers of a version's uploads, lowest first.
  def tagged_builds(version)
    @shell.run('git', 'tag', '--list', "testflight/#{version}-*").split.map { |tag| tag[/-(\d+)\z/, 1].to_i }.sort
  end

  # The version an uploaded build belongs to, from its tag.
  def version_of_build(build)
    tags = @shell.run('git', 'tag', '--list', "testflight/*-#{build}").split
    raise TrainError, "expected one testflight/*-#{build} tag, found #{tags.length}" unless tags.length == 1

    tags.first[%r{\Atestflight/(.+)-\d+\z}, 1]
  end

  # Puts a signed tag on the commit and pushes it. Safe to repeat: a tag that is already there is only pushed.
  def tag(name, commit, message)
    if tag?(name)
      raise TrainError, "#{name} already marks another commit" unless commit("refs/tags/#{name}") == commit
    else
      @shell.run('git', 'tag', '-s', name, commit, '-m', message)
    end
    @shell.run('git', 'push', '--quiet', 'origin', "refs/tags/#{name}")
  end

  def create_branch(name, commit)
    @shell.run('git', 'push', '--quiet', 'origin', "#{commit}:refs/heads/#{name}")
  end

  def delete_branch(name)
    @shell.run('git', 'push', '--quiet', 'origin', '--delete', name)
  end

  # Commits the files (path => text) on a new branch from origin/main and pushes it. The work happens in a worktree
  # of its own, so the checkout, which other sessions share, stays as it is.
  def commit_on_branch(branch:, message:, files:)
    Dir.mktmpdir('release-train') do |parent|
      dir = File.join(parent, 'worktree')
      @shell.run('git', 'worktree', 'add', '--quiet', '-b', branch, dir, 'origin/main')
      begin
        files.each { |path, text| File.write(File.join(dir, path), text) }
        @shell.in(dir).run('git', 'commit', '--quiet', '-S', '-m', message, '--', *files.keys)
        @shell.in(dir).run('git', 'push', '--quiet', 'origin', "#{branch}:refs/heads/#{branch}")
      ensure
        @shell.run('git', 'worktree', 'remove', '--force', dir)
        @shell.run('git', 'branch', '--quiet', '-D', branch)
      end
    end
  end
end
