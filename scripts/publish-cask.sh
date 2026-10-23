#!/usr/bin/env bash
# Points the Homebrew cask at the current release and publishes it to the tap.
# Run after `gh release create vX.Y.Z build/MacZones-X.Y.Z.zip ...`.
# Usage: scripts/publish-cask.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TAP=tralots/homebrew-tap
CASK=packaging/homebrew/maczones.rb
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
URL="https://github.com/tralots/MacZones/releases/download/v$VERSION/MacZones-$VERSION.zip"

# Hash the asset users will actually download, not the local build.
SHA=$(curl -fsSL "$URL" | shasum -a 256 | awk '{print $1}')
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

EXISTING=$(gh api "repos/$TAP/contents/Casks/maczones.rb" --jq .sha 2>/dev/null || true)
gh api -X PUT "repos/$TAP/contents/Casks/maczones.rb" \
  -f message="maczones $VERSION" \
  -f content="$(base64 < "$CASK")" \
  ${EXISTING:+-f sha="$EXISTING"} >/dev/null
echo "Published maczones $VERSION ($SHA) to $TAP. Commit $CASK too."
