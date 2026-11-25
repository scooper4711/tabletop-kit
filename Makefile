.PHONY: build build-ios test test-scripts lint coverage clean attribution-gaps

build:
	swift build

# Builds the libraries for the iPad simulator, as the apps use them there.
build-ios:
	xcodebuild -scheme TabletopKit-Package -destination 'generic/platform=iOS Simulator' -quiet build

test:
	swift test

lint:
	swiftlint --strict --quiet

# Runs the tests and fails when the libraries' line or region coverage is below 80%.
coverage:
	scripts/coverage.sh

clean:
	rm -rf .build coverage

# Checks the Mac App Store packaging script on a generated trial app, the iCloud entitlements script on a generated
# app, the library backup scripts on a made-up home folder, the store listing and TestFlight scripts against
# stand-ins for fastlane and xcodebuild, and the release train in a made-up repository.
test-scripts:
	scripts/test-package-appstore.sh
	scripts/test-add-icloud-entitlements.sh
	scripts/test-libraries-backup.sh
	scripts/test-store-scripts.sh
	ruby scripts/test-testflight-internal.rb
	ruby scripts/test-ios-store-profiles.rb
	ruby scripts/test-changelog.rb
	ruby scripts/test-train-repository.rb
	ruby scripts/test-train-store.rb
	ruby scripts/test-public-beta.rb
	ruby scripts/test-release-train.rb

# Writes docs/source-attribution-gaps.md, the attribution facts still to fill in by hand, from the source catalog and
# the apps' source lists in docs/source-usage.
attribution-gaps:
	swift run -q SourceAttributionTool gaps docs/source-usage docs/source-attribution-gaps.md
