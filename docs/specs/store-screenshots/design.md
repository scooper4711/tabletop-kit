# Store screenshots: design

`store-screenshots.sh` clones each simulator, erases and boots the clone, overrides its status bar, and runs
`-only-testing:<App>UITests/StoreScreenshots` with `TEST_RUNNER_SCREENSHOT_DIR` set to a scratch folder. `<App>` is the
scheme's name up to its first hyphen; `UI_TESTS` overrides it. Pictures are checked with `sips` and move into the
output folder only after both devices succeed. `scripts/test-store-scripts.sh` covers it with stand-ins.

## Mac

`store-screenshots-mac.sh` opens the bundle with `open -a`, passing `LAUNCH_ENV` as `--env`, `OPEN_FILE` as a document
and `-NSRequiresAquaSystemAppearance YES` ahead of the app's own arguments. System Events puts the window at 300,60 at
1440x900; `CLICKS` are posted as Core Graphics mouse events (AppleScript clicks don't reach SwiftUI grids). The
picture is `screencapture -l` of the window of that size, found with `CGWindowListCopyWindowInfo`, without a shadow.
The app is quit afterward unless `KEEP_RUNNING=1`. `scripts/test-store-scripts.sh` checks the argument handling; the
rest needs a screen.

