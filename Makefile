.PHONY: build build-ios test test-scripts lint coverage clean

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
# app, and the library backup scripts on a made-up home folder.
test-scripts:
	scripts/test-package-appstore.sh
	scripts/test-add-icloud-entitlements.sh
	scripts/test-libraries-backup.sh
