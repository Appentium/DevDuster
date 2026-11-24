#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

out=build/release
archive=$out/DevDuster.xcarchive
version=$(sed -nE 's/^ *MARKETING_VERSION: "?([^"]+)"?$/\1/p' project.yml)
build=$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: "?([^"]+)"?$/\1/p' project.yml)
tag="v$version"
sparkle_bin=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin

if [[ "${1:-}" != "--resume" ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }
  ! gh release view "$tag" >/dev/null 2>&1 || { echo "$tag already exists; bump MARKETING_VERSION in project.yml."; exit 1; }
  rm -rf "$out" && mkdir -p "$out"
  xcodegen generate --quiet
  echo "Archiving $tag…"
  xcodebuild -project DevDuster.xcodeproj -scheme DevDuster -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" archive -quiet
  echo "Signing with Developer ID and uploading to Apple…"
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$out/upload" -allowProvisioningUpdates -quiet
fi

echo "Waiting for Apple to notarize (usually minutes, sometimes over an hour)…"
for attempt in {1..360}; do
  if xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$out/notarized" > "$out/notarize.log" 2>&1; then
    break
  fi
  # Still processing or a network timeout means try again; anything else is a rejection or a real error.
  grep -qE "is processing|timed out|NSURLErrorDomain" "$out/notarize.log" || { tail -5 "$out/notarize.log"; exit 1; }
  sleep 30
done

app="$out/notarized/DevDuster.app"
[[ -d "$app" ]] || { echo "Notarization did not finish in 3 hours; rerun with --resume."; exit 1; }
xcrun stapler validate "$app"
spctl --assess --type execute "$app"

ditto -c -k --keepParent "$app" "$out/DevDuster.zip"

[[ -x "$sparkle_bin/sign_update" ]] || xcodebuild -resolvePackageDependencies -project DevDuster.xcodeproj -scheme DevDuster -derivedDataPath build/DerivedData -quiet
# sign_update reads the private EdDSA key from the login Keychain and prints sparkle:edSignature and length.
signature=$("$sparkle_bin/sign_update" "$out/DevDuster.zip")
[[ "$signature" =~ 'sparkle:edSignature="([^"]+)" length="([0-9]+)"' ]] || { echo "Could not sign the zip: $signature"; exit 1; }
scripts/update_appcast.py website/appcast.xml "$version" "$build" "${match[2]}" "${match[1]}" \
  "https://github.com/Appentium/DevDuster/releases/download/$tag/DevDuster.zip"

sed -i '' -E -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$(shasum -a 256 "$out/DevDuster.zip" | cut -d' ' -f1)\"/" packaging/homebrew/devduster.rb

gh release create "$tag" "$out/DevDuster.zip" --title "DevDuster $version" --generate-notes
echo "Published $tag. Commit website/appcast.xml and packaging/homebrew/devduster.rb, copy the cask to the tap, then run make site and upload build/devduster-site.zip."
