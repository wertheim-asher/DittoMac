#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DittoMac"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
APP_DIR="build/${APP_NAME}.app"
FINAL_DMG="build/${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="build/dmg-staging"
RW_DMG="build/${APP_NAME}-rw.dmg"
VOLUME_NAME="${APP_NAME}"

echo "==> Building ${APP_NAME}.app first"
./Scripts/build_app.sh

if [ ! -d "${APP_DIR}" ]; then
    echo "error: ${APP_DIR} not found after build" >&2
    exit 1
fi

echo "==> Staging DMG contents"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_DIR}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> Creating writable DMG for layout styling"
rm -f "${RW_DMG}" "${FINAL_DMG}"
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${STAGING_DIR}" -ov -fs HFS+ -format UDRW "${RW_DMG}"

echo "==> Mounting and styling window layout"
MOUNT_OUTPUT=$(hdiutil attach "${RW_DMG}" -readwrite -noverify -noautoopen)
DEVICE=$(echo "$MOUNT_OUTPUT" | grep -E '^/dev/' | sed -n '1p' | awk '{print $1}')

sleep 1

osascript <<OSA
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 112
        set the bounds of container window to {200, 120, 720, 500}
        delay 1
        -- Compute icon positions from the *actual* resulting bounds rather than assuming the
        -- request above took effect exactly — Finder doesn't always honor it precisely on the
        -- first pass, and hardcoded icon positions would then end up off-center.
        set b to the bounds of container window
        set winWidth to (item 3 of b) - (item 1 of b)
        set winHeight to (item 4 of b) - (item 2 of b)
        set iconY to ((winHeight / 2) - 30) as integer
        set position of item "${APP_NAME}.app" of container window to {(winWidth / 4) as integer, iconY}
        set position of item "Applications" of container window to {(winWidth * 3 / 4) as integer, iconY}
        close
        open
        set the bounds of container window to {200, 120, 720, 500}
        update without registering applications
        delay 3
    end tell
end tell
OSA

echo "==> Waiting for Finder to flush .DS_Store before unmounting"
sync
sleep 3

echo "==> Unmounting"
hdiutil detach "${DEVICE}"

echo "==> Converting to compressed final DMG"
hdiutil convert "${RW_DMG}" -format UDZO -ov -o "${FINAL_DMG}"
rm -f "${RW_DMG}"
rm -rf "${STAGING_DIR}"

echo "==> Done: ${FINAL_DMG}"
echo ""
echo "This app is ad-hoc signed, not notarized by Apple. On first launch, your friends will need to:"
echo "  1. Right-click (or Control-click) DittoMac.app in Applications and choose Open, then confirm Open in the dialog"
echo "     — this bypasses Gatekeeper's default block, which only offers 'Move to Trash' on a plain double-click."
echo "  2. If that doesn't work: System Settings > Privacy & Security > scroll down to the blocked-app notice > Open Anyway."
