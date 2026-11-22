# Store screenshots: design

`store-screenshots.sh` clones each simulator, erases and boots the clone, overrides its status bar, and runs
`-only-testing:<App>UITests/StoreScreenshots` with `TEST_RUNNER_SCREENSHOT_DIR` set to a scratch folder. `<App>` is the
scheme's name up to its first hyphen; `UI_TESTS` overrides it. Pictures are checked with `sips` and move into the
output folder only after both devices succeed. `scripts/test-store-scripts.sh` covers it with stand-ins.
