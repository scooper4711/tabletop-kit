# Mac App Store build: design

`scripts/package-appstore.sh <app> <entitlements> <bundle-id>` is the one shared script. An app reaches it at
`.build/checkouts/tabletop-kit/scripts/package-appstore.sh` after `swift package resolve`, so the version of the
script follows the dependency pin.

1. Copy the app to `build/appstore/`, so the disk image's bundle stays as built.
2. Icon: `iconutil` unpacks `AppIcon.icns` into an iconset, which becomes a temporary `AppIcon.appiconset` in a
   temporary asset catalog; `actool --compile` writes `Assets.car` and an `AppIcon.icns` beside it, for the app's own
   `LSMinimumSystemVersion`. No catalog is committed in the apps.
3. `Info.plist`: `CFBundleVersion` = `BUILD_NUMBER`, `ITSAppUsesNonExemptEncryption` = false, and `CFBundleIconName`
   from actool's partial Info.plist (ITMS-90236).
4. Profile: `PROVISIONING_PROFILE` (a file) is copied to `Contents/embedded.provisionprofile`.
5. Entitlements: a copy of the file the app passes for this channel, with the two identifiers from `TEAM_ID` and the
   bundle ID set (replaced when the file already names them, as entitlements with iCloud do). An app whose App Store
   build drops an entitlement only its updater needs, or adds iCloud, passes a channel-specific file; the profile
   must allow everything in it.
6. `codesign` with `APP_SIGNING_IDENTITY`, then `productbuild --component <app> /Applications --sign
   INSTALLER_IDENTITY` to `build/appstore/<name>.pkg`.
7. With `UPLOAD=1`, `xcrun altool --validate-app` then `--upload-package` with the API key.

`TRIAL=1` signs ad hoc, removes any profile the disk image build embedded, skips the installer signature, and so exercises 1-3 and 5 on any Mac,
including CI. `scripts/test-package-appstore.sh` runs a trial package of a tiny generated app and checks `Assets.car`,
the icon name, the deployment target, the plist keys, the entitlements and the `.pkg` payload.
