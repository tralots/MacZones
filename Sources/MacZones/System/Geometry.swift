import AppKit

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }

    var roundedToPixels: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }

    func approxEqual(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// Distance from a point to the rect (0 when inside).
    func distance(to p: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - p.x, 0, p.x - maxX)
        let dy = Swift.max(minY - p.y, 0, p.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Cocoa (bottom-left origin) ⇄ Accessibility/Quartz (top-left origin of the primary display).
/// The transform is its own inverse, so the same call converts both ways.
enum Coords {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func flip(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Stable across reboots and reconnects (unlike `displayID`), used to remember per-display layouts.
    var stableID: String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            return string as String
        }
        return "display-\(displayID)"
    }

    /// Screen containing a Cocoa point, or the nearest one.
    static func at(_ point: CGPoint) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
            ?? screens.min { $0.frame.distance(to: point) < $1.frame.distance(to: point) }
    }

    static func with(id: String) -> NSScreen? {
        screens.first { $0.stableID == id }
    }

    /// Screen holding most of a Cocoa rect.
    static func best(for rect: CGRect) -> NSScreen? {
        screens.max { $0.frame.intersection(rect).area < $1.frame.intersection(rect).area }
    }
}
