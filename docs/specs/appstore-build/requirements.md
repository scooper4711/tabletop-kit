# Mac App Store build: requirements

Every Tableside Toolkit app ships a Mac App Store build beside its notarized disk image (tabletop-kit#23). The steps
live here once, as scripts the apps call from their SwiftPM checkout of tabletop-kit.

## R1 One code base, two channels
- R1.1 An app builds its App Store channel from the same sources as its disk image, with `CHANNEL=appstore` in its
  `scripts/build-app.sh`. That compiles with `-DAPP_STORE`, so the app can leave out its updater and outside
  payment links.
- R1.2 The disk image channel is unchanged: no flag, Developer ID signing, notarization.

## R2 The package
- R2.1 `scripts/package-appstore.sh` turns a built app into a signed installer package: it compiles the app icon
  into `Assets.car` (ITMS-90546) for the app's own minimum system and names it in `CFBundleIconName` (ITMS-90236),
  embeds the Mac App Store provisioning profile, signs with an Apple Distribution
  identity and wraps the app with `productbuild` and a Mac Installer Distribution identity.
- R2.2 The signing entitlements gain `com.apple.application-identifier` (team ID, a dot, the bundle ID) and
  `com.apple.developer.team-identifier`, which App Store Connect requires; the rest stays as the app's entitlements for
  this channel say, which may differ from its disk image's (no Downloads folder without the updater, iCloud).
- R2.3 The bundle declares `ITSAppUsesNonExemptEncryption` as false (HTTPS only) and carries a build number
  that increases with every upload (`BUILD_NUMBER`); the marketing version doesn't change.
- R2.4 Without the identities or the profile, the script says what is missing and stops. `TRIAL=1` instead builds an
  ad hoc signed, unsigned-installer package that checks everything else, and can't be uploaded.
- R2.5 No file in the package carries the quarantine attribute (ITMS-91109), which a profile or resource downloaded
  with a browser brings along.

## R3 Upload
- R3.1 `VALIDATE=1` only validates the package with App Store Connect. `UPLOAD=1` validates the package and uploads it to App Store Connect with `xcrun altool`, using an App Store
  Connect API key from the environment (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_FILE`).
- R3.2 Certificates and keys come from the environment or repository secrets, never from the repository.
