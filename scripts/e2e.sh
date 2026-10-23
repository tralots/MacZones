#!/usr/bin/env bash
# Real-input end-to-end test. MOVES YOUR MOUSE for ~5 s, so hands off.
# Requires: MacZones running with Accessibility, and Accessibility for this terminal.
# Usage: scripts/e2e.sh [overlay-screenshot.png]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=.build/e2e
mkdir -p "$OUT"
swiftc -O scripts/e2e/MZTarget.swift -o "$OUT/MZTarget"
swiftc -O scripts/e2e/MZDrive.swift -o "$OUT/MZDrive"
pgrep -x MacZones >/dev/null || { echo "MacZones is not running (scripts/build.sh run)"; exit 1; }
"$OUT/MZTarget" &
TARGET=$!
trap 'kill $TARGET 2>/dev/null || true' EXIT
sleep 2
"$OUT/MZDrive" "$@"
