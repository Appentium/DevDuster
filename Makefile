DERIVED_DATA := build/DerivedData

.PHONY: gen build test release site

gen:
	xcodegen generate

build:
	xcodebuild -project DevDuster.xcodeproj -scheme DevDuster -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA) build

test:
	cd Packages/DusterCore && swift test
	@if [ -d Tests ]; then xcodebuild -project DevDuster.xcodeproj -scheme DevDuster -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA) test; fi

release:
	scripts/release.sh

site:
	rm -rf build/site build/devduster-site.zip
	mkdir -p build/site
	cp -R website/. build/site/
	rm build/site/DEPLOY.md
	cd build/site && zip -qr ../devduster-site.zip . -x '.DS_Store' '*/.DS_Store'
	@echo "Upload build/devduster-site.zip to public_html (see website/DEPLOY.md)"
