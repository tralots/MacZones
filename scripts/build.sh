#!/usr/bin/env bash
# Builds build/MacZones.app.
# Usage: scripts/build.sh [run|install|release]
#   run      kill any running copy and launch the fresh build
#   install  copy to /Applications and launch from there
#   release  universal (arm64 + x86_64) build zipped to build/MacZones-<version>.zip,
#            notarized + stapled when a Developer ID identity and the notary profile exist
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
# Prefer Developer ID for every build, so dev and release builds share one Accessibility grant.
find_identity() { security find-identity -v -p codesigning | awk -F'"' -v kind="$1" '$0 ~ kind {print $2; exit}'; }
IDENTITY="${SIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
IDENTITY="${IDENTITY:-$(find_identity "Apple Development")}"
SIGN_FLAGS=()
# Notarization requires the hardened runtime and a secure timestamp.
[[ "$IDENTITY" == "Developer ID Application"* ]] && SIGN_FLAGS=(--options runtime --timestamp)
codesign --force ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} --sign "${IDENTITY:--}" "$APP"
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
    NOTARY_PROFILE=${NOTARY_PROFILE:-MacZones}
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    if [[ "$IDENTITY" == "Developer ID Application"* ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
      xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
      xcrun stapler staple "$APP"
      rm -f "$ZIP"
      ditto -c -k --keepParent "$APP" "$ZIP" # re-zip so the stapled ticket ships
      spctl --assess --type execute -v "$APP"
      echo "Notarized."
    else
      echo "Not notarized (needs a Developer ID Application identity + notarytool profile '$NOTARY_PROFILE')."
    fi
    echo "Packaged $ZIP ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"
    ;;
esac
