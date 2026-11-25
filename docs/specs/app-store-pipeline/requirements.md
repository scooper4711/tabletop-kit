# App Store pipeline: requirements

Shared by the Tableside apps' manual App Store workflows.

- R1 Signing runs on a GitHub-hosted runner from an `app-store` Environment that only `main`, `release/*` branches
  and `v*` tags can use.
- R2 A build stops unless its tree is clean, its version is open, and its commit is on the branch that may build
  (`docs/specs/release-train` R1.3, R1.4):
  - R2.1 A version whose `v<version>` tag exists is closed.
  - R2.2 While no `origin/release/*` branch exists, the commit must be on `origin/main`.
  - R2.3 While one exists, the commit must be on `origin/release/<version>`, the version being
    `scripts/version.sh marketing`.
- R3 The Mac package is universal, carries the commit's build number, is signed, and names the app's bundle identifier.
  An app that syncs must have its iCloud entitlement in the signed app.
- R4 Delivery to internal testers waits until Apple has processed the build, then sets its What to Test note.
- R5 Delivery only ever adds a build to groups Apple marks as internal. It never adds one to an external group, never
  submits for beta review or App Review, and stops if the app has no internal group.
- R6 Delivery stops with the app, build and state named if processing fails or doesn't finish in time.
