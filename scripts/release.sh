#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

out=build/release
archive=$out/DevDuster.xcarchive
version=$(sed -nE 's/^ *MARKETING_VERSION: "?([^"]+)"?$/\1/p' project.yml)
tag="v$version"

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
  # Anything other than "still processing" is a rejection or a real error.
  grep -q "is processing" "$out/notarize.log" || { tail -5 "$out/notarize.log"; exit 1; }
  sleep 30
done

app="$out/notarized/DevDuster.app"
[[ -d "$app" ]] || { echo "Notarization did not finish in 3 hours; rerun with --resume."; exit 1; }
xcrun stapler validate "$app"
spctl --assess --type execute "$app"

ditto -c -k --keepParent "$app" "$out/DevDuster.zip"
gh release create "$tag" "$out/DevDuster.zip" --title "DevDuster $version" --generate-notes
echo "Published $tag"
