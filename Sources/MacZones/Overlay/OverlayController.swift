import AppKit

struct OverlayStyle: Equatable {
    var zone: NSColor
    var highlight: NSColor
    var border: NSColor
    var opacity: CGFloat
    var showNumbers: Bool

    init(_ s: Settings) {
        zone = NSColor(hex: s.zoneColor) ?? .black
        highlight = NSColor(hex: s.highlightColor) ?? .controlAccentColor
        border = NSColor(hex: s.borderColor) ?? .white
        opacity = s.overlayOpacity
        showNumbers = s.showZoneNumbers
    }
}

/// Owns one transparent, click-through panel per screen and draws zones into it.
@MainActor
final class OverlayController {
    private let state: AppState
    private var windows: [String: OverlayWindow] = [:]
    private var hideWork: DispatchWorkItem?

    init(state: AppState) {
        self.state = state
    }

    /// Shows zones on `screens`, highlighting `highlight.indices` on the screen with id `highlight.screenID`.
    func show(on screens: [NSScreen], highlight: (screenID: String, indices: Set<Int>)? = nil) {
        hideWork?.cancel()
        let style = OverlayStyle(state.settings)
        let ids = Set(screens.map(\.stableID))

        for screen in screens {
            let window = window(for: screen)
            let origin = screen.frame.origin
            let zones = state.zoneRects(for: screen).map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
            let lit = highlight?.screenID == screen.stableID ? highlight?.indices ?? [] : []
            window.zoneView.update(zones: zones, highlighted: lit, style: style)

            if !window.isVisible {
                window.alphaValue = 0
                window.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    window.animator().alphaValue = 1
                }
            } else if window.alphaValue < 1 {
                // Interrupt a running fade-out (an animator call replaces the in-flight animation).
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.08
                    window.animator().alphaValue = 1
                }
            }
        }
        for (id, window) in windows where !ids.contains(id) {
            window.orderOut(nil)
        }
    }

    func hide() {
        hideWork?.cancel()
        windows.values.forEach { $0.orderOut(nil) }
    }

    /// Briefly shows a screen's zones (layout switched, appearance preview).
    func flash(_ screen: NSScreen, duration: TimeInterval = 0.9) {
        show(on: [screen])
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func screensChanged() {
        windows.values.forEach { $0.orderOut(nil) }
        windows = [:]
    }

    private func fadeOut() {
        let visible = windows.values.filter(\.isVisible)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            visible.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated {
                visible.filter { $0.alphaValue == 0 }.forEach { $0.orderOut(nil) }
            }
        })
    }

    private func window(for screen: NSScreen) -> OverlayWindow {
        if let window = windows[screen.stableID] {
            if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
            return window
        }
        let window = OverlayWindow(screen: screen)
        windows[screen.stableID] = window
        return window
    }
}

final class OverlayWindow: NSPanel {
    let zoneView = ZoneOverlayView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Above regular and floating windows so zones are visible over the window being dragged.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = zoneView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ZoneOverlayView: NSView {
    private var zones: [CGRect] = []
    private var highlighted: Set<Int> = []
    private var style = OverlayStyle(Settings())

    func update(zones: [CGRect], highlighted: Set<Int>, style: OverlayStyle) {
        // Called on every mouse move while dragging; only redraw when something visible changed.
        guard zones != self.zones || highlighted != self.highlighted || style != self.style else { return }
        self.zones = zones
        self.highlighted = highlighted
        self.style = style
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Big zones first so nested/overlapping smaller zones stay visible on top.
        let order = zones.indices.sorted { zones[$0].area > zones[$1].area }
        for i in order {
            drawZone(zones[i], number: i + 1, lit: highlighted.contains(i))
        }
        if highlighted.count > 1 {
            let union = highlighted.map { zones[$0] }.reduce(CGRect.null) { $0.union($1) }
            let path = NSBezierPath(roundedRect: union.insetBy(dx: -3, dy: -3), xRadius: 14, yRadius: 14)
            path.lineWidth = 2
            path.setLineDash([8, 6], count: 2, phase: 0)
            style.highlight.withAlphaComponent(0.9).setStroke()
            path.stroke()
        }
    }

    private func drawZone(_ rect: CGRect, number: Int, lit: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        let fill = lit ? style.highlight.withAlphaComponent(min(1, style.opacity + 0.2))
                       : style.zone.withAlphaComponent(style.opacity)
        fill.setFill()
        path.fill()
        (lit ? style.highlight.blended(withFraction: 0.35, of: .white) ?? style.highlight
             : style.border.withAlphaComponent(0.4)).setStroke()
        path.lineWidth = lit ? 3 : 1.5
        path.stroke()

        guard style.showNumbers || lit else { return }
        let size = min(rect.height * 0.28, rect.width * 0.28, 84)
        var lines: [(String, NSFont, CGFloat)] = []
        if style.showNumbers {
            lines.append(("\(number)", .systemFont(ofSize: size, weight: .bold).rounded, 0.92))
        }
        if lit {
            let caption = "\(Int(rect.width)) × \(Int(rect.height))"
            lines.append((caption, .monospacedDigitSystemFont(ofSize: max(11, size * 0.22), weight: .medium), 0.8))
        }
        let rendered = lines.map { text, font, alpha in
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            ])
        }
        let total = rendered.reduce(0) { $0 + $1.size().height }
        var y = rect.midY + total / 2
        for line in rendered {
            let s = line.size()
            y -= s.height
            line.draw(at: CGPoint(x: rect.midX - s.width / 2, y: y))
        }
    }
}

extension NSFont {
    var rounded: NSFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
