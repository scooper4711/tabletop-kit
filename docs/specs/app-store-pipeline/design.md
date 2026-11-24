# App Store pipeline: design

Each app's `.github/workflows/appstore.yml` checks out this repository at a pinned commit and runs these scripts, so a
fix to them doesn't need a kit release or a change to the app's `Package.resolved`. The exception is the iPad archive:
the apps' `make ipad-archive` runs `archive-ios.sh` from `.build/checkouts/tabletop-kit`, the version in
`Package.resolved`, so a fix there reaches the pipeline only with a kit release and a dependency update.

- `add-store-signing.sh` loads the certificates into a temporary keychain and writes the profile and API key to the
  runner's temporary folder. It loads no iOS profile: `archive-ios.sh` gets those from the API (store-listing R3.5).
- `check-store-release.sh` holds the source and package guards (R2, R3).
- `testflight-internal.rb` and `ios-store-profiles.rb` talk to the App Store Connect API with Ruby's standard
  library, through `app_store_connect_client.rb`. A group is used only when its `isInternalGroup` attribute is true
  (R5). Groups with access to all builds get the build from Apple, so it adds the build only to the others.
