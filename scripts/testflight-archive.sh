#!/usr/bin/env bash
#
# Archive MINATO for App Store / TestFlight and export a signed .ipa.
# See docs/TESTFLIGHT.md for the full release process (App Store Connect side,
# build-number bumping, and the upload step).
#
# Usage:  scripts/testflight-archive.sh
# Output: build/export/*.ipa  (upload with Transporter or `xcrun altool`)
#
# Notes:
#  - Release signing/team come from Configs/Local.xcconfig (DEVELOPMENT_TEAM,
#    PRODUCT_BUNDLE_IDENTIFIER) — make sure it points at YOUR App Store app.
#  - Automatic signing may need a one-time Xcode login (Product > Archive in the
#    GUI is the simplest first run; this script is for repeat/CI use).

set -euo pipefail

PROJECT="bitchat.xcodeproj"
SCHEME="bitchat (iOS)"
ARCHIVE_PATH="build/MINATO.xcarchive"
EXPORT_PATH="build/export"
EXPORT_OPTIONS="Configs/ExportOptions.plist"

echo "▸ Archiving $SCHEME (Release)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -skipPackagePluginValidation \
  -allowProvisioningUpdates \
  archive

echo "▸ Exporting .ipa via $EXPORT_OPTIONS…"
rm -rf "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

echo "✓ Done. IPA(s):"
ls -1 "$EXPORT_PATH"/*.ipa 2>/dev/null || echo "  (no .ipa — check export output above)"
echo ""
echo "Next: upload to App Store Connect —"
echo "  • Transporter.app (drag the .ipa), or"
echo "  • xcrun altool --upload-app -f $EXPORT_PATH/<name>.ipa --type ios \\"
echo "      --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>   (ASC API key in ~/.appstoreconnect/private_keys)"
