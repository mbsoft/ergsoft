#!/bin/bash
# Build ErgSoft for App Store submission.
#   scripts/release.sh            → regenerate project, archive, validate, open Organizer
#   scripts/release.sh --upload   → also upload to App Store Connect (uses your Xcode account)
#   BUILD=7 scripts/release.sh    → override the build number (default: next after the last archive)
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=ErgSoft
ARCHIVE_DIR=build/archives
EXPORT_DIR=build/export
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"

# --- build number: bump automatically unless BUILD is given -------------------------------
LAST=$(ls "$ARCHIVE_DIR" 2>/dev/null | grep -oE 'build-[0-9]+' | sed 's/build-//' | sort -n | tail -1 || true)
BUILD=${BUILD:-$(( ${LAST:-0} + 1 ))}
VERSION=$(grep -m1 'CFBundleShortVersionString' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
echo "▶ ErgSoft $VERSION ($BUILD)"
sed -i '' -E "s/(CFBundleVersion: )\"[0-9]+\"/\1\"$BUILD\"/g" project.yml

# --- project ----------------------------------------------------------------------------------
command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

# --- archive ----------------------------------------------------------------------------------
ARCHIVE="$ARCHIVE_DIR/ErgSoft-$VERSION-build-$BUILD.xcarchive"
xcodebuild -project ErgSoft.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates archive | xcpretty 2>/dev/null || \
xcodebuild -project ErgSoft.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates archive -quiet

# --- export + validate ------------------------------------------------------------------------
cat > "$EXPORT_DIR/options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([ "${1:-}" = "--upload" ] && echo upload || echo export)</string>
  <key>teamID</key><string>6TJKVTB5Y8</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_DIR/options.plist" \
  -exportPath "$EXPORT_DIR/$VERSION-$BUILD" -allowProvisioningUpdates -quiet

if [ "${1:-}" = "--upload" ]; then
  echo "✔ Uploaded ErgSoft $VERSION ($BUILD) to App Store Connect — it appears under TestFlight in ~10 min."
else
  echo "✔ Archived and exported: $EXPORT_DIR/$VERSION-$BUILD/ErgSoft.ipa"
  echo "  Opening Organizer — select the archive, Validate App, then Distribute App → App Store Connect."
  open -a Xcode "$ARCHIVE"
fi
git add project.yml >/dev/null 2>&1 || true
