#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/ClaudeUsage"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="ClaudeUsage"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path)"

echo "=== Building $APP_NAME (Universal Binary) ==="

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

SWIFT_FILES=(
    "$SRC_DIR/Models.swift"
    "$SRC_DIR/CredentialManager.swift"
    "$SRC_DIR/UsageViewModel.swift"
    "$SRC_DIR/UsagePopoverView.swift"
    "$SRC_DIR/ClaudeUsageApp.swift"
)

FRAMEWORKS="-framework SwiftUI -framework ServiceManagement"

# Build arm64 (Apple Silicon)
echo "Compiling arm64..."
swiftc \
    -o "$BUILD_DIR/$APP_NAME-arm64" \
    -target arm64-apple-macosx13.0 \
    -sdk "$SDK" \
    $FRAMEWORKS \
    -O \
    "${SWIFT_FILES[@]}"

# Build x86_64 (Intel)
echo "Compiling x86_64..."
swiftc \
    -o "$BUILD_DIR/$APP_NAME-x86_64" \
    -target x86_64-apple-macosx13.0 \
    -sdk "$SDK" \
    $FRAMEWORKS \
    -O \
    "${SWIFT_FILES[@]}"

# Create Universal Binary
echo "Creating Universal Binary..."
lipo -create \
    "$BUILD_DIR/$APP_NAME-arm64" \
    "$BUILD_DIR/$APP_NAME-x86_64" \
    -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Clean intermediate binaries
rm "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"

# Copy Info.plist
cp "$SRC_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Verify
echo ""
echo "=== Build complete ==="
file "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo ""
echo "App: $APP_BUNDLE"
echo ""
echo "To run:    open \"$APP_BUNDLE\""
echo "To install: cp -r \"$APP_BUNDLE\" /Applications/"
echo "To create DMG: ./create_dmg.sh"
