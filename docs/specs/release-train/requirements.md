# Release train: requirements

How a Tableside app's version travels from `main` to the App Store, so that one commit is what the store has. Before
this, a `v*` tag opened a version and every later build shipped under its name, so the tag, the changelog and the
store build pointed at different commits.

Issues: tabletop-kit#95 (these scripts) and tabletop-kit#96 (the whole change). The build pipeline the train starts
is in `docs/specs/app-store-pipeline`.

## R1 The train
- R1.1 `VERSION` on `main` names the version being worked toward. The build number is the commit count.
- R1.2 Every upload is tagged `testflight/<version>-<build>` on the commit it was built from. The tag is signed.
- R1.3 A version that goes to App Review gets a branch `release/<version>`, cut at the submitted build. While any
  `release/*` branch exists, builds come only from that version's branch: a fix there has a lower commit count than
  `main`, and Mac build numbers may never go down.
- R1.4 `v<version>` marks the build Apple accepted, and nothing else. A version with that tag is closed: nothing is
  uploaded or submitted under it again.
- R1.5 Both platforms ship the same build under the same version, released by hand.
- R1.6 One version is with App Review at a time.

## R2 `release-train.rb upload [note]`
- R2.1 Starts the app's `appstore.yml` on `main`, or on the release branch while a version is in review (R1.3), with
  upload and delivery to the internal testers, and follows the run.
- R2.2 The What to Test note is the one given, or else the changelog's Unreleased section (R6.2). Without either, or
  with a note over 4,000 characters, nothing is started.
- R2.3 When the run succeeds, the commit it built gets its tag (R1.2), which is pushed.
- R2.4 A build number Apple already has is not built again: the commit is only tagged. This finishes an upload whose
  tagging failed.

## R3 `release-train.rb status`
- R3.1 Says the version and where it stands: open on `main`, in review on its branch, or closed.
- R3.2 For each platform: the newest TestFlight build of the version with its internal and external states, and the
  App Store record's state and build.
- R3.3 Lists the version's uploads that have no tag.

## R4 Public beta
- R4.1 `public-beta.rb <bundle-id> <build>` adds the build, iPad and Mac, to the app's external group named
  "Public beta", and submits it for Beta App Review where Apple says the build is ready for that. It never builds or
  uploads, and never writes to another group.
- R4.2 It promotes only a build that is processed, has its tag (R1.2) and has a What to Test note, on both platforms.
  If either platform fails a check, neither is promoted.
- R4.3 `release-train.rb beta [build]` starts the app's `public-beta.yml` for a tagged build, by default the version's
  newest, and follows the run. This workflow is the only way a build reaches the external group.

## R5 App Review
- R5.1 `release-train.rb submit <build>` takes a tagged build of an open version. It attaches the build to the version
  being prepared on both platforms, names that version, sets its release to manual (R1.5), and submits both.
- R5.2 Every check comes before any change: the build is processed on both platforms and was uploaded as this
  version, each platform has a version that can be edited, and neither has a submission in progress.
- R5.3 The release branch is cut at the build's commit once the checks pass (R1.3). A resubmitted build must be on
  the branch that is already there.
- R5.4 `release-train.rb accept` stops unless Apple has accepted the version on both platforms with the same build.
- R5.5 It then tags that build's commit `v<version>` (signed), and creates a GitHub release with that tag, whose
  notes are the changelog's Unreleased section at that commit, and which has no files.
- R5.6 A release branch that holds commits `main` lacks gets a pull request into `main`, and `accept` stops there
  until it is merged. A branch `main` already contains is deleted.
- R5.7 Last, a pull request sets `VERSION` to the next patch version and splits the changelog (R6.3).

## R6 The changelog
- R6.1 An app's `CHANGELOG.md` has an `## [Unreleased]` section that describes the build at that commit.
- R6.2 As a What to Test note the section is plain text ("Added:" for "### Added"), cut at a line end to fit 4,000
  characters.
- R6.3 On acceptance, the entries that were in the section at the `v*` commit move under `## [<version>] - <date>`,
  with the link to the release. Entries merged during the review stay under Unreleased.

## R7 Safety
- R7.1 Every command can be run again after it stopped halfway: a step that is done is skipped.
- R7.2 The commands never change the checkout's working tree or branch, which other work may be using. The commit
  for R5.7 is made in a worktree of its own.
- R7.3 The App Store Connect key comes from `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_FILE`, as for every script.
- R7.4 Submitting stays a person's decision: nothing here runs `submit` or `accept` on its own.
