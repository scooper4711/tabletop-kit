# Release train: design

`release-train.rb` is run on the releasing Mac, from the app's checkout: signed tags need the developer's key, which
a workflow doesn't have. `public-beta.rb` runs in the app's `public-beta.yml` workflow, in the `app-store`
environment, from a checkout of this repository at a pinned commit, like the scripts of `app-store-pipeline`.

| File | What it holds |
|---|---|
| `release-train.rb` | The commands `status`, `upload`, `beta` and `submit` (`ReleaseTrain`) |
| `train_acceptance.rb` | `accept` (`TrainAcceptance`) |
| `train_repository.rb` | git: origin's branches and tags, signed tags, a commit made in a worktree |
| `train_github.rb` | `gh`: workflow runs, releases, pull requests |
| `train_store.rb` | App Store Connect: builds, App Store versions, review submissions |
| `changelog.rb` | The Unreleased section: read, as a note, and split (R6) |
| `public-beta.rb` | The promotion (R4.1, R4.2) |

## Reading the repository

Every command fetches first and then reads `origin/*` and tags, never the working tree (R7.2). The bundle identifier
is the `BUNDLE_ID` in `origin/main`'s `appstore.yml`. Branches and tags are pushed by commit
(`git push origin <commit>:refs/heads/release/<version>`), so no branch is checked out.

A tag that exists on the same commit is only pushed again; one on another commit stops the command (R7.1).

## Upload

`gh workflow run` prints the run it started; an older gh doesn't, and then the newest `workflow_dispatch` run of the
workflow is polled until one newer than before appears. After `gh run watch --exit-status`, the tag goes on the run's
`headSha`, not on what `origin` was before: `main` may have moved between the fetch and the dispatch.

## Submitting (R5.1 to R5.3)

The calls are the ones fastlane's *deliver* makes:

1. `PATCH /v1/appStoreVersions/{id}` with `versionString`, `releaseType: MANUAL` and the build, for both platforms.
   The record is the platform's version in an editable state (`PREPARE_FOR_SUBMISSION`, the rejected states,
   `INVALID_BINARY`). The store listing push creates it; without one, `submit` stops.
2. Per platform: `POST /v1/reviewSubmissions`, `POST /v1/reviewSubmissionItems` for the version, a wait for the
   version to become `READY_FOR_REVIEW`, then `PATCH /v1/reviewSubmissions/{id}` with `submitted: true`.

Both builds are attached before either platform is submitted, so a platform that refuses its build stops the other
from going to review alone. An unsent submission from an earlier try (`READY_FOR_REVIEW`) is used again, unless it
holds something other than this version.

A platform with a submission that is `WAITING_FOR_REVIEW`, `IN_REVIEW` or `UNRESOLVED_ISSUES` stops `submit`. After a
rejection the old submission is `UNRESOLVED_ISSUES`: how it is resubmitted through the API hasn't been tried yet, so
for now that step is done in App Store Connect.

## Accepting (R5.4 to R5.7)

A version counts as accepted in `PENDING_DEVELOPER_RELEASE`, `PENDING_APPLE_RELEASE`, `PROCESSING_FOR_DISTRIBUTION`,
`READY_FOR_DISTRIBUTION` or `READY_FOR_SALE`, so `accept` works before and after the release is made.

The steps run in order, each skipped when done: tag, GitHub release, merge back, delete the branch, next version.
The merge back comes before the next version's pull request on purpose. That pull request rewrites the Unreleased
section, and a fix's changelog line arrives through the merge: made in the other order, the two would conflict on
GitHub, which ignores `.gitattributes`' `merge=union`.

The next version is the next patch. A release with features gets its number from a pull request that raises
`VERSION` before the first upload.

## Public beta (R4)

Apple forbids `GET /v1/builds/{id}/betaGroups`, so the group's builds are listed instead. A build is submitted for
Beta App Review only when its `externalBuildState` is `READY_FOR_BETA_SUBMISSION`: a build of a version Apple already
approved goes to the testers without a submission. The tag is looked up on `origin` with `git ls-remote`, so the
workflow needs no tags in its checkout.

## Tests

`make test-scripts` runs them. The repository tests make a scratch checkout with a bare origin and sign with an SSH
key made on the spot, so they read no keychain. GitHub and App Store Connect are stand-ins that record what was
asked.
