DERIVED_DATA := build/DerivedData

.PHONY: gen build test release

gen:
	xcodegen generate

build:
	xcodebuild -project DevDuster.xcodeproj -scheme DevDuster -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA) build

test:
	cd Packages/DusterCore && swift test
	@if [ -d Tests ]; then xcodebuild -project DevDuster.xcodeproj -scheme DevDuster -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA) test; fi

release:
	scripts/release.sh
