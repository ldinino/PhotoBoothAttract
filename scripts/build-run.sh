#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/PhotoBoothAttract.xcodeproj"
SCHEME="PhotoBoothAttract"
CONFIG="Debug"
APP_NAME="PhotoBoothAttract"
DERIVED_DATA="/tmp/PhotoBoothAttract-build-debug"

echo "==> Building $SCHEME ($CONFIG)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    ONLY_ACTIVE_ARCH=YES \
    build \
    2>&1 | tail -5

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIG/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: Build output not found at $BUILT_APP"
    exit 1
fi

echo "==> Launching $APP_NAME..."
open "$BUILT_APP"
