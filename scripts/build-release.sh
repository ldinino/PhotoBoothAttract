#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/PhotoBoothAttract.xcodeproj"
SCHEME="PhotoBoothAttract"
CONFIG="Release"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="PhotoBoothAttract"
DERIVED_DATA="/tmp/PhotoBoothAttract-build"

rm -rf "$DIST_DIR" "$DERIVED_DATA"
mkdir -p "$DIST_DIR"

echo "==> Clean building $SCHEME ($CONFIG) for arm64 + x86_64..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64 x86_64" \
    clean build \
    2>&1 | tail -5

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIG/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: Build output not found at $BUILT_APP"
    exit 1
fi

cp -R "$BUILT_APP" "$DIST_DIR/"
rm -rf "$DERIVED_DATA"

APP_PATH="$DIST_DIR/$APP_NAME.app"
BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"

echo ""
echo "==> Verifying universal binary..."
ARCHS_OUTPUT=$(lipo -info "$BINARY")
echo "    $ARCHS_OUTPUT"

if ! echo "$ARCHS_OUTPUT" | grep -q "arm64"; then
    echo "ERROR: arm64 slice missing"; exit 1
fi
if ! echo "$ARCHS_OUTPUT" | grep -q "x86_64"; then
    echo "ERROR: x86_64 slice missing"; exit 1
fi

echo "==> Verifying app icon..."
ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
if [ ! -f "$ICON_PATH" ]; then
    echo "ERROR: AppIcon.icns not found in bundle"; exit 1
fi
ICON_SIZE=$(stat -f%z "$ICON_PATH")
if [ "$ICON_SIZE" -lt 1000 ]; then
    echo "ERROR: AppIcon.icns looks too small ($ICON_SIZE bytes)"; exit 1
fi
echo "    AppIcon.icns present ($(du -h "$ICON_PATH" | cut -f1))"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
echo "==> Version: $VERSION (build $BUILD_NUM)"

ZIP_NAME="${APP_NAME}-v${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
echo "==> Packaging $ZIP_NAME..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "    $(du -h "$ZIP_PATH" | cut -f1) $ZIP_PATH"

echo ""
echo "=== Build complete ==="
echo "App:  $APP_PATH"
echo "Zip:  $ZIP_PATH"
echo ""
echo "To publish a new release:"
echo "  gh release create v${VERSION} \"$ZIP_PATH\" --title \"v${VERSION}\" --notes \"Release v${VERSION}\""
echo "To update an existing release:"
echo "  gh release upload v${VERSION} \"$ZIP_PATH\" --clobber"
