#!/usr/bin/env bash
# Builds build/MacZones.app.
# Usage: scripts/build.sh [run|install|release]
#   run      kill any running copy and launch the fresh build
#   install  copy to /Applications and launch from there
#   release  universal (arm64 + x86_64) build zipped to build/MacZones-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=MacZones
CONFIG=${CONFIG:-release}
BUILD_DIR=build
APP="$BUILD_DIR/$APP_NAME.app"

ARCH_FLAGS=()
[[ "${1:-}" == release ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/$APP_NAME"

if [[ ! -f Resources/AppIcon.icns ]]; then
  rm -rf "$BUILD_DIR/AppIcon.iconset"
  swift scripts/make-icon.swift "$BUILD_DIR/AppIcon.iconset"
  iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A stable signing identity keeps the Accessibility grant valid across rebuilds
# (ad-hoc signatures change every build, forcing the user to re-grant access).
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

case "${1:-}" in
  run)
    pkill -x "$APP_NAME" || true
    open "$APP"
    ;;
  install)
    pkill -x "$APP_NAME" || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    ;;
  release)
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packaged $ZIP ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"
    ;;
esac
