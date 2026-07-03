#!/usr/bin/env bash
#
# build-release.sh — produce a distributable Containers .dmg from source.
#
# Archives the app in Release configuration, exports it, and wraps it in a DMG.
# Signing is driven entirely by environment variables so the same script serves
# both a fully-signed CI release and an unsigned local/PR build:
#
#   VERSION           marketing version to stamp (required, e.g. 1.2.0)
#   SIGNING_IDENTITY  Developer ID Application identity; empty → unsigned build
#   TEAM_ID           Apple Developer team ID (required when signing)
#
# When SIGNING_IDENTITY is set the app is archived with manual Developer ID
# signing and exported via `-exportArchive` (hardened runtime, secure
# timestamp) so it is notarization-ready. When empty, the app is archived with
# signing disabled and copied straight out of the archive — handy for CI smoke
# builds, but Gatekeeper will quarantine it on other machines.
#
# Output: dist/ContainerUI-<VERSION>.dmg
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="ContainerUI"
APP_NAME="ContainerUI"     # PRODUCT_NAME → ContainerUI.app
VOLUME_NAME="ContainerUI"

VERSION="${VERSION:?set VERSION (e.g. VERSION=1.2.0)}"
# Monotonic CFBundleVersion; Sparkle requires it to strictly increase.
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"

BUILD_DIR="build"
DIST_DIR="dist"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/${VOLUME_NAME}-${VERSION}.dmg"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# The project isn't checked in; regenerate it if it's missing.
if [[ ! -d "$SCHEME.xcodeproj" ]]; then
  echo "==> Generating Xcode project"
  xcodegen generate
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "==> Archiving (signed: $SIGNING_IDENTITY)"
  xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID"

  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

  echo "==> Exporting Developer ID app"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR"
else
  echo "==> Archiving (unsigned — not for distribution)"
  xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO
  mkdir -p "$EXPORT_DIR"
  cp -R "$ARCHIVE/Products/Applications/$APP_NAME.app" "$APP_PATH"
fi

echo "==> Packaging DMG"
scripts/package-dmg.sh "$APP_PATH" "$DMG_PATH" "$VOLUME_NAME"

# Surface the artifact path to callers (e.g. the release workflow).
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "DMG_PATH=$DMG_PATH" >> "$GITHUB_ENV"
fi
echo "==> Done: $DMG_PATH"
