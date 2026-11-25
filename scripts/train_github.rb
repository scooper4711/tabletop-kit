# frozen_string_literal: true

# What release-train.rb asks of GitHub, through the gh command: workflow runs, releases and pull requests.
# Specified in docs/specs/release-train.

require_relative 'train_repository'

# The app's repository on GitHub. gh finds it from the checkout's origin.
class TrainGitHub
  POLL_SECONDS = 5
  POLLS = 24

  def initialize(shell, sleeper: ->(seconds) { sleep seconds })
    @shell = shell
    @sleeper = sleeper
  end

  def url
    @shell.run('gh', 'repo', 'view', '--json', 'url', '--jq', '.url')
  end

  # Starts the workflow on the branch and gives the run's number.
  def dispatch(workflow, branch, inputs)
    before = newest_run(workflow)
    fields = inputs.flat_map { |name, value| ['-f', "#{name}=#{value}"] }
    output = @shell.run('gh', 'workflow', 'run', workflow, '--ref', branch, *fields)
    output[%r{/actions/runs/(\d+)}, 1] || wait_for_run(workflow, before)
  end

  # Follows the run on the terminal, and stops the train if the run fails.
  def watch(run)
    @shell.watch('gh', 'run', 'watch', run, '--exit-status')
  end

  def run_commit(run)
    @shell.run('gh', 'run', 'view', run, '--json', 'headSha', '--jq', '.headSha')
  end

  def release?(tag)
    @shell.ok?('gh', 'release', 'view', tag)
  end

  # A release with notes and nothing to download: the store has the app.
  def create_release(tag, notes)
    @shell.run('gh', 'release', 'create', tag, '--verify-tag', '--latest', '--title', tag, '--notes', notes)
  end

  # The open pull requests from the branch, as their addresses.
  def pull_requests(branch)
    @shell.run('gh', 'pr', 'list', '--head', branch, '--state', 'open', '--json', 'url', '--jq', '.[].url').split
  end

  def create_pull_request(branch:, title:, body:)
    @shell.run('gh', 'pr', 'create', '--base', 'main', '--head', branch, '--title', title, '--body', body)
  end

  private

  def newest_run(workflow)
    @shell.run('gh', 'run', 'list', '--workflow', workflow, '--event', 'workflow_dispatch', '--limit', '1',
               '--json', 'databaseId', '--jq', '.[0].databaseId // 0').to_i
  end

  # Older versions of gh don't say which run they started, so this waits for one newer than the last.
  def wait_for_run(workflow, before)
    POLLS.times do
      newest = newest_run(workflow)
      return newest.to_s if newest > before

      @sleeper.call(POLL_SECONDS)
    end
    raise TrainError, "#{workflow} was started, but its run didn't show up"
  end
end
