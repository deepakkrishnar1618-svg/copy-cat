#!/bin/bash
# Builds Copy Cat and packages it as a distributable DMG.
# Usage: bash scripts/make-dmg.sh
set -euo pipefail

APP_NAME="Copy Cat"
VERSION="2.6.1"
DMG_NAME="CopyCat-${VERSION}.dmg"
DERIVED_DATA="build/DerivedData"
BUILD_DIR="${DERIVED_DATA}/Build/Products/Release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

echo "→ Building ${APP_NAME} ${VERSION}..."
xcodebuild \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E "^(error:|warning: |Build succeeded|\*\* BUILD)"

if [ ! -d "$APP_PATH" ]; then
  echo "✗ Build failed — ${APP_PATH} not found"
  exit 1
fi

echo "→ Staging..."
STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "→ Creating DMG..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDBZ \
  "${DMG_NAME}"

rm -rf "$STAGING"
echo ""
echo "✓ Done: ${DMG_NAME}"
echo "  Attach to a GitHub release at: https://github.com/deepakkrishnar1618-svg/copy-cat/releases"
