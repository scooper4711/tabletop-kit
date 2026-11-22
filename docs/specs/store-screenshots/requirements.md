# Store screenshots: requirements

Each app's App Store screenshots are made from its demo library by one command, at sizes App Store Connect accepts.

- R1.1 `scripts/store-screenshots.sh <project> <scheme> <out-dir>` runs the app's `StoreScreenshots` UI test class on
  an iPhone 18 Pro (6.3-inch; App Store Connect refused this project's 6.9-inch set) and an iPad Pro 13-inch.
- R1.2 Pictures land in `<out-dir>` as `iphone-<name>.png` and `ipad-<name>.png`.
- R1.3 Each run uses a fresh copy of the simulator, which is deleted afterward, so saved app state can't reach a picture.
- R1.4 The status bar shows a fixed time and full signal and battery.
- R1.5 A failed test or a picture of the wrong size stops the script and leaves `<out-dir>` as it was.
