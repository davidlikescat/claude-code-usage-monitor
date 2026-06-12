#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="ClaudeUsage"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="ClaudeUsage-1.0"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
STAGING="$BUILD_DIR/dmg-staging"

# Build first if needed
if [ ! -d "$APP_BUNDLE" ]; then
    echo "App not found. Building first..."
    "$SCRIPT_DIR/build.sh"
fi

echo "=== Creating DMG ==="

# Clean staging
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"

# Copy app to staging
cp -r "$APP_BUNDLE" "$STAGING/"

# Create Applications symlink (drag-to-install)
ln -s /Applications "$STAGING/Applications"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Clean staging
rm -rf "$STAGING"

echo ""
echo "=== DMG created ==="
echo "File: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "Upload this to GitHub Releases for distribution."
