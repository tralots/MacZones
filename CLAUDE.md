# MacZones

FancyZones-style window snapping for macOS. Menu bar app (no Dock icon unless its window is open).
Drag a window while holding a modifier (default ⇧ Shift) → zone overlay appears → release over a zone → window snaps to it.

## Build & run

```bash
scripts/build.sh          # build build/MacZones.app (release)
scripts/build.sh run      # build, kill running copy, launch
scripts/build.sh install  # build, copy to /Applications, launch
scripts/build.sh release  # universal arm64+x86_64 build → build/MacZones-<version>.zip
swift build               # compile only (fast type-check loop)
```

### Releasing (public repo: github.com/tralots/MacZones)

1. Bump `CFBundleShortVersionString` + `CFBundleVersion` in `Resources/Info.plist`.
2. `scripts/build.sh release`, commit, push.
3. `gh release create vX.Y.Z build/MacZones-X.Y.Z.zip --title "MacZones X.Y.Z" --notes "..."`.
4. `scripts/update-cask.sh` → hashes the published zip and updates `Casks/maczones.rb`. Commit + push = live
   (users get it on `brew update`). Check: `brew audit --cask --strict --online tralots/maczones/maczones`.

### Homebrew cask notes (Homebrew 7.x)

- No separate tap repo (user's choice): this repo *is* the tap via its root `Casks/` folder.
  `brew tap tralots/maczones https://github.com/tralots/MacZones && brew install --cask maczones`.
  A one-command `brew install tralots/x/y` would need a repo named `homebrew-*` — deliberately not done.
- Official homebrew/cask rejects non-notarized apps.
- Until notarized, the cask clears quarantine in `postflight_steps` (old `postflight do … system_command` is
  deprecated in Homebrew 7). Steps run sandboxed: `args` paths use `{{appdir}}` placeholders and need
  `writable_paths` + `writable_base: :appdir`. Drop that block once releases are notarized.
- `depends_on macos: :sonoma` (string form `">= :sonoma"` is deprecated).
- The user's `/Applications/MacZones.app` is brew-managed; `scripts/build.sh install` still works for dev builds
  (overwrites it; brew keeps reporting the cask version until the next `brew upgrade`).

## Architecture

| Path | Role |
|------|------|
| `App/main.swift`, `App/AppDelegate.swift` | Entry point, wiring, main menu, permission polling, hotkey registration |
| `Model/Layout.swift` | `Zone` (normalized 0…1 rect, origin top-left), `ZoneLayout`, `LayoutTemplate`, `ZoneGeometry` (zones → screen rects with spacing) |
| `Model/Settings.swift` | `Settings` struct (tolerant decoding: missing keys fall back to defaults), `ModifierKey`, `ActivationMode` |
| `Model/AppState.swift` | Single `ObservableObject` store. Persists `Config` JSON to `~/Library/Application Support/MacZones/config.json` (debounced) |
| `System/AXWindow.swift` | Accessibility wrapper: window under point, focused window, get/set frame |
| `System/Geometry.swift` | Coordinate flipping (Cocoa ⇄ AX), `NSScreen.stableID`, rect helpers |
| `System/HotKeys.swift` | Carbon `RegisterEventHotKey` wrapper (no extra permission needed) |
| `Snapping/SnapController.swift` | Core: global mouse monitors → drag detection → zone hit-testing → snap. Keyboard zone moves |
| `Overlay/OverlayController.swift` | Transparent click-through panels per screen that draw zones |
| `UI/*` | SwiftUI settings window (Layouts, Behavior, Appearance, Shortcuts, General) + layout canvas editor + status menu |
| `Tests/MacZonesTests` | XCTest unit tests (`@testable import MacZones`) |
| `scripts/` | `build.sh` (bundle + sign), `make-icon.swift`, `update-cask.sh`, `e2e.sh` + `e2e/` (real-input harness) |
| `Casks/maczones.rb` | Homebrew cask; repo doubles as its own tap |

(Source paths above are relative to `Sources/MacZones/`.)

## Key facts / gotchas

- **Coordinates**: Cocoa/NSScreen = bottom-left origin. AX + CGEvent = top-left origin of the *primary* screen.
  Convert only via `Coords.flip` (self-inverse). Zones are stored top-left normalized against `screen.visibleFrame`.
- **Drag detection** (`SnapController`): on first `leftMouseDragged` look up the AX window under the cursor, then
  treat it as a window move only when its position changes and size does not. Give up after ≥48px **and** ≥0.35 s
  without the window moving (text selection etc.) so we don't poll AX for every drag.
  The AX position of a dragged window lags the cursor by ~5 events (~90 ms) — a distance-only give-up broke fast drags.
- **Modifier state** is read from `NSEvent.modifierFlags` on every drag event, so it works even if `flagsChanged`
  global events are blocked; `flagsChanged` only makes the overlay react without mouse movement.
- **Snap apply**: set size → position → size (cross-display moves), with `AXEnhancedUserInterface` temporarily off
  (otherwise some apps animate/ignore). Re-applied once after 250 ms because macOS native tiling can fight us.
- **Multi-zone**: hold span key (default ⌃) → bounding box from anchor zone to hovered zone; or "proximity" mode.
- **Overlapping zones**: hit test picks the smallest zone containing the cursor; otherwise nearest zone.
- **Layout per display** keyed by display UUID (`NSScreen.stableID`); unassigned displays use the first layout.
- Native macOS tiling (15+) uses ⌥ while dragging — warn if the user picks Option as activation key.
- Global monitors never see events for MacZones' own windows (expected).
- Config is written only after the first change (`AppState` debounced save); absence of `config.json` = defaults.
- Synthesized input gotchas (e2e): raw `CGEvent` key posts don't fire Carbon hotkeys reliably and can leave
  modifiers stuck (a stuck ⌃ turns the next click into a right-click) → use `osascript` System Events for hotkeys.
  Grab title bars ≥150 px from the left edge, or you hit the traffic-light buttons and nothing drags.

## Conventions

- Keep files small and single-purpose; `@MainActor` on anything touching AppKit/AX/state.
- Settings additions: add the field with a default in `Settings` **and** a line in its `init(from:)`.
- Update this file when adding features, files, or discovering platform gotchas.
