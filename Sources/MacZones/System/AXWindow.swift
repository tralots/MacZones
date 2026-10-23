import AppKit
import ApplicationServices

extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success ? value : nil
    }

    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool? {
        value(attribute) as? Bool
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func point(_ attribute: String) -> CGPoint? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    func size(_ attribute: String) -> CGSize? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    var pid: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(self, &pid)
        return pid
    }
}

/// A window of another app, addressed through the Accessibility API. Frames are in AX (top-left) coordinates.
struct AXWindow: Hashable {
    let element: AXUIElement
    let pid: pid_t

    static func == (a: AXWindow, b: AXWindow) -> Bool { CFEqual(a.element, b.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }

    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // Never let a hung app freeze our event handling.
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }()

    /// Window under a point given in AX coordinates.
    static func at(_ point: CGPoint) -> AXWindow? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        return window(containing: hit)
    }

    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let window = axApp.element(kAXFocusedWindowAttribute) else { return nil }
        return AXWindow(element: window, pid: app.processIdentifier)
    }

    private static func window(containing element: AXUIElement) -> AXWindow? {
        let pid = element.pid
        guard pid != getpid() else { return nil }
        var current: AXUIElement? = element
        for _ in 0..<32 {
            guard let node = current else { break }
            if node.string(kAXRoleAttribute) == kAXWindowRole { return AXWindow(element: node, pid: pid) }
            if let window = node.element(kAXWindowAttribute) { return AXWindow(element: window, pid: pid) }
            current = node.element(kAXParentAttribute)
        }
        return nil
    }

    var frame: CGRect? {
        guard let origin = element.point(kAXPositionAttribute),
              let size = element.size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var isFullScreen: Bool { element.bool("AXFullScreen") ?? false }

    var isMovable: Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    func setFrame(_ rect: CGRect) {
        // Apps with AXEnhancedUserInterface on (VoiceOver, some Electron apps) animate or drop frame changes.
        let app = AXUIElementCreateApplication(pid)
        let enhanced = app.bool("AXEnhancedUserInterface") ?? false
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) } }

        // Size → position → size: the first resize may be clamped by the old display, the second fixes it.
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
    }

    private func setPosition(_ point: CGPoint) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) { element.set(kAXPositionAttribute, value) }
    }

    private func setSize(_ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) { element.set(kAXSizeAttribute, value) }
    }
}

enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow accessibility" prompt (only once per app identity).
    static func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
