# Store screenshots: requirements

Each app's App Store screenshots are made from its demo library by one command, at sizes App Store Connect accepts.

- R1.1 `scripts/store-screenshots.sh <project> <scheme> <out-dir>` runs the app's `StoreScreenshots` UI test class on
  an iPhone 18 Pro (6.3-inch; App Store Connect refused this project's 6.9-inch set) and an iPad Pro 13-inch.
- R1.2 Pictures land in `<out-dir>` as `iphone-<name>.png` and `ipad-<name>.png`.
- R1.3 Each run uses a fresh copy of the simulator, which is deleted afterward, so saved app state can't reach a picture.
- R1.4 The status bar shows a fixed time and full signal and battery.
- R1.5 A failed test or a picture of the wrong size stops the script and leaves `<out-dir>` as it was.

## Mac

- R2.1 `scripts/store-screenshots-mac.sh <app-bundle> <out-file.png> [launch-argument...]` launches a built Mac app,
  sizes its window to 1440x900, saves a picture of that window, and quits the app.
- R2.2 The app always opens in the light appearance, whatever the Mac is set to, and the pointer is moved off the
  window, so no control looks hovered.
- R2.3 `LAUNCH_ENV`, `OPEN_FILE`, `CLICKS` and `BEFORE_CAPTURE` stage what the picture shows: environment variables,
  a document, real mouse clicks at window-relative points, and an AppleScript run in System Events.
- R2.4 It needs a desktop session with Screen Recording and Accessibility for the terminal, so it runs on a Mac
  someone is logged in to, never on the CI mini. It refuses to run when the app is already open, which could be
  someone's own copy.

