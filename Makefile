DERIVED_DATA := build/DerivedData

.PHONY: gen build test

gen:
	xcodegen generate

build:
	xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA) build

test:
	cd Packages/SweepCore && swift test
	@if [ -d Tests ]; then xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA) test; fi
