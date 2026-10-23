import AppKit

/// Watches global mouse events, detects window drags, shows zones and snaps windows into them.
@MainActor
final class SnapController {
    private let state: AppState
    private let overlay: OverlayController
    private var monitors: [Any] = []
    private var session: DragSession?
    /// Windows we snapped, so we can restore their size when they are dragged back out.
    private var snapped: [AXWindow: SnapRecord] = [:]

    private final class DragSession {
        let mouseDown: CGPoint
        let startedAt = Date()
        var lookedUp = false
        var window: AXWindow?
        var startFrame: CGRect? // AX coordinates
        var moving = false
        var toggled = false
        var spanAnchor: (screenID: String, index: Int)?
        var target: CGRect? // Cocoa coordinates

        init(mouseDown: CGPoint) { self.mouseDown = mouseDown }
    }

    private struct SnapRecord {
        var originalSize: CGSize
        var snappedFrame: CGRect // AX coordinates
    }

    /// Mouse travel and time without the window following before we decide it's not a window drag.
    /// Both are needed: the AX position of a dragged window lags the cursor by a few events.
    private let giveUpDistance: CGFloat = 48
    private let giveUpDelay: TimeInterval = 0.35

    init(state: AppState, overlay: OverlayController) {
        self.state = state
        self.overlay = overlay
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .flagsChanged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        session = nil
        overlay.hide()
    }

    // MARK: - Mouse

    private func handle(_ event: NSEvent) {
        debugLog("event \(event.type.rawValue) trusted=\(state.axTrusted) session=\(session != nil)")
        switch event.type {
        case .leftMouseDown:
            session = state.settings.enabled && state.axTrusted ? DragSession(mouseDown: NSEvent.mouseLocation) : nil
        case .leftMouseDragged:
            dragged()
        case .leftMouseUp:
            released()
        case .rightMouseDown:
            if let session, session.moving, state.settings.rightClickToggles {
                session.toggled.toggle()
                refresh()
            }
        case .flagsChanged:
            refresh()
        default:
            break
        }
    }

    private func dragged() {
        guard let s = session else { return }
        let mouse = NSEvent.mouseLocation

        if !s.lookedUp {
            s.lookedUp = true
            let window = AXWindow.at(Coords.flip(mouse))
            debugLog("lookup at \(Coords.flip(mouse)) → \(String(describing: window?.frame)) movable=\(window?.isMovable ?? false)")
            guard let window, window.isMovable, !window.isFullScreen else {
                session = nil
                return
            }
            s.window = window
            s.startFrame = window.frame
            return
        }

        if !s.moving {
            guard let window = s.window, let start = s.startFrame, let frame = window.frame else {
                session = nil
                return
            }
            if frame.size != start.size {
                session = nil // resizing, not moving
                return
            }
            debugLog("check start=\(start) now=\(frame)")
            if frame.origin == start.origin {
                if hypot(mouse.x - s.mouseDown.x, mouse.y - s.mouseDown.y) > giveUpDistance,
                   Date().timeIntervalSince(s.startedAt) > giveUpDelay {
                    session = nil
                }
                return
            }
            s.moving = true
        }
        refresh()
    }

    /// Recomputes zone activation and the hovered zones for the current mouse/modifier state.
    private func refresh() {
        guard let s = session, s.moving else { return }
        let settings = state.settings
        let flags = NSEvent.modifierFlags
        let keyHeld = settings.activationKey.isHeld(in: flags)
        var active = settings.activationMode == .holdKey ? keyHeld : !keyHeld
        if s.toggled { active.toggle() }

        guard active else {
            s.target = nil
            s.spanAnchor = nil
            overlay.hide()
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.at(mouse) else { return }
        let screenID = screen.stableID
        let rects = state.zoneRects(for: screen)
        var indices: Set<Int> = []

        if let base = ZoneGeometry.hitTest(mouse, in: rects) {
            if settings.spanKey != settings.activationKey, settings.spanKey.isHeld(in: flags) {
                if s.spanAnchor?.screenID != screenID || !(rects.indices ~= s.spanAnchor!.index) {
                    s.spanAnchor = (screenID, base)
                }
                indices = ZoneGeometry.span(from: s.spanAnchor!.index, to: base, in: rects)
            } else {
                s.spanAnchor = nil
                indices = settings.spanByProximity
                    ? ZoneGeometry.proximity(mouse, base: base, in: rects, distance: settings.zoneSpacing + 16)
                    : [base]
            }
        }

        s.target = indices.isEmpty ? nil : indices.map { rects[$0] }.reduce(CGRect.null) { $0.union($1) }
        let screens = settings.showOnAllDisplays ? NSScreen.screens : [screen]
        overlay.show(on: screens, highlight: (screenID, indices))
    }

    private func released() {
        guard let s = session else { return }
        session = nil
        overlay.hide()
        guard s.moving, let window = s.window else { return }

        if let target = s.target {
            snap(window, to: Coords.flip(target), originalSize: s.startFrame?.size)
        } else if let record = snapped.removeValue(forKey: window) {
            // Dragged out of a zone: give the window its pre-snap size back, keeping the grab point under the cursor.
            guard state.settings.restoreSizeOnUnsnap,
                  let start = s.startFrame, start.approxEqual(record.snappedFrame, tolerance: 4),
                  let current = window.frame else { return }
            let mouse = Coords.flip(NSEvent.mouseLocation)
            let ratio = current.width > 0 ? (mouse.x - current.minX) / current.width : 0.5
            let size = record.originalSize
            window.setFrame(CGRect(x: mouse.x - ratio * size.width, y: current.minY,
                                   width: size.width, height: size.height))
        }
    }

    // MARK: - Snapping

    /// `frame` in AX coordinates.
    private func snap(_ window: AXWindow, to frame: CGRect, originalSize: CGSize?) {
        let original = snapped[window]?.originalSize ?? originalSize ?? window.frame?.size ?? frame.size
        if snapped.count > 256 { snapped = snapped.filter { $0.key.frame != nil } }
        snapped[window] = SnapRecord(originalSize: original, snappedFrame: frame)

        window.setFrame(frame)
        // macOS native tiling or slow apps may override the first attempt; check once more.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard self?.session?.moving != true,
                  let current = window.frame, !current.approxEqual(frame, tolerance: 2) else { return }
            window.setFrame(frame)
        }
    }

    // MARK: - Keyboard actions

    /// Moves the focused window to the next/previous zone, crossing to the adjacent display at the ends.
    func moveFocusedWindow(by step: Int) {
        debugLog("hotkey move \(step) focused=\(String(describing: AXWindow.focused()?.frame))")
        guard state.axTrusted, let window = AXWindow.focused(), let axFrame = window.frame else { return }
        let frame = Coords.flip(axFrame)
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard let screen = NSScreen.best(for: frame) else { return }
        let rects = state.zoneRects(for: screen)
        guard !rects.isEmpty else { return }

        var target: CGRect
        if let current = rects.firstIndex(where: { $0.approxEqual(frame, tolerance: 12) }) {
            let next = current + step
            if rects.indices.contains(next) {
                target = rects[next]
            } else if screens.count > 1, let i = screens.firstIndex(where: { $0.stableID == screen.stableID }) {
                let other = screens[(i + step + screens.count) % screens.count]
                let otherRects = state.zoneRects(for: other)
                guard let first = otherRects.first, let last = otherRects.last else { return }
                target = step > 0 ? first : last
            } else {
                target = rects[(next + rects.count) % rects.count]
            }
        } else {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard let nearest = ZoneGeometry.hitTest(center, in: rects) else { return }
            target = rects[nearest]
        }
        snap(window, to: Coords.flip(target), originalSize: axFrame.size)
    }

    /// Gives the focused window its pre-snap size back, centered on where it is now.
    func restoreFocusedWindow() {
        guard state.axTrusted, let window = AXWindow.focused(),
              let record = snapped.removeValue(forKey: window), let current = window.frame else { return }
        let size = record.originalSize
        window.setFrame(CGRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2,
                               width: size.width, height: size.height))
    }

    /// Applies layout number `n` (1-based) to the display under the mouse.
    func applyLayout(number n: Int) {
        guard state.layouts.indices.contains(n - 1), let screen = NSScreen.at(NSEvent.mouseLocation) else { return }
        state.assign(state.layouts[n - 1].id, to: screen)
    }
}

/// Writes to stderr when launched with `-MZDebug YES`, e.g. `open --stderr /tmp/mz.log MacZones.app --args -MZDebug YES`.
private let debugLogging = UserDefaults.standard.bool(forKey: "MZDebug")

func debugLog(_ message: @autoclosure () -> String) {
    guard debugLogging else { return }
    FileHandle.standardError.write(Data("MZ \(message())\n".utf8))
}
