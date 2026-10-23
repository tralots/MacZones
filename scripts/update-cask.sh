#!/usr/bin/env bash
# Points Casks/maczones.rb at the current release. Commit + push afterwards; `brew update` picks it up.
# Run after `gh release create vX.Y.Z build/MacZones-X.Y.Z.zip ...`.
# Usage: scripts/update-cask.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CASK=Casks/maczones.rb
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
URL="https://github.com/tralots/MacZones/releases/download/v$VERSION/MacZones-$VERSION.zip"

# Hash the asset users will actually download, not the local build.
SHA=$(curl -fsSL "$URL" | shasum -a 256 | awk '{print $1}')
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
echo "$CASK → $VERSION ($SHA). Commit and push to publish."
