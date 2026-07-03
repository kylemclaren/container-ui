#!/usr/bin/env bash
#
# package-dmg.sh — wrap a built .app in a distributable, compressed .dmg.
#
# The DMG contains the app plus a symlink to /Applications so users can
# drag-to-install. If `create-dmg` (Homebrew) is available it's used for a
# tidy Finder layout; otherwise we fall back to plain `hdiutil`, which needs
# no dependencies and works headlessly in CI.
#
# Usage:
#   scripts/package-dmg.sh <path/to/App.app> <output.dmg> [volume-name]
#
# Example:
#   scripts/package-dmg.sh build/export/ContainerUI.app dist/ContainerUI-1.2.0.dmg "ContainerUI"
#
set -euo pipefail

APP_PATH="${1:?usage: package-dmg.sh <App.app> <output.dmg> [volume-name]}"
DMG_PATH="${2:?usage: package-dmg.sh <App.app> <output.dmg> [volume-name]}"
VOLUME_NAME="${3:-$(basename "${APP_PATH%.app}")}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app not found at $APP_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
  echo "==> Packaging with create-dmg"
  # create-dmg exits non-zero if it can't set the (cosmetic) code-sign on the
  # DMG; the DMG is still produced, so we don't treat that as fatal.
  create-dmg \
    --volname "$VOLUME_NAME" \
    --window-pos 200 120 \
    --window-size 640 400 \
    --icon-size 120 \
    --icon "$(basename "$APP_PATH")" 170 190 \
    --app-drop-link 470 190 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH" \
    || true
  if [[ -f "$DMG_PATH" ]]; then
    echo "==> Created $DMG_PATH"
    exit 0
  fi
  echo "warning: create-dmg did not produce an image; falling back to hdiutil" >&2
fi

echo "==> Packaging with hdiutil"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH"

echo "==> Created $DMG_PATH"
