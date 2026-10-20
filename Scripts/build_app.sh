#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DittoMac"
BUNDLE_ID="com.dittomac.app"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> Done: ${APP_DIR}"
echo "Note: ad-hoc signing means macOS treats each rebuild as a new app identity —"
echo "Accessibility/Local Network permission grants will need to be re-approved after rebuilds"
echo "unless you sign with a persistent Developer ID certificate."
