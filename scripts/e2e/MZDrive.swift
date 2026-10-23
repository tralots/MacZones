// End-to-end driver: synthesizes real mouse input against the MZTarget window and checks where it lands.
// Needs Accessibility for the terminal running it. Usage: MZDrive [overlay-screenshot.png]
import AppKit
import Carbon.HIToolbox

let primary = NSScreen.screens[0]
let primaryH = primary.frame.height
func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height) }

// Expected zones come from MacZones' own config: the primary display's layout and spacing.
func expectedZones() -> [CGRect] {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MacZones/config.json")
    let config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    let settings = config["settings"] as? [String: Any] ?? [:]
    let spacing = settings["zoneSpacing"] as? CGFloat ?? 8
    let layouts = config["layouts"] as? [[String: Any]] ?? []
    let displayID = primary.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
    let uuid = CFUUIDCreateString(nil, CGDisplayCreateUUIDFromDisplayID(displayID)!.takeRetainedValue())! as String
    let assigned = (config["assignments"] as? [String: String])?[uuid]
    // No config yet (nothing changed since install) → MacZones' default first layout, Priority Grid 25/50/25.
    let defaults: [[String: Any]] = [["x": 0, "y": 0, "w": 0.25, "h": 1], ["x": 0.25, "y": 0, "w": 0.5, "h": 1],
                                     ["x": 0.75, "y": 0, "w": 0.25, "h": 1]]
    let layout = layouts.first(where: { $0["id"] as? String == assigned }) ?? layouts.first
    let zones = layout?["zones"] as? [[String: Any]] ?? defaults
    let half = spacing / 2
    let inner = primary.visibleFrame.insetBy(dx: half, dy: half)
    return zones.map { zone in
        let z = { (k: String) in CGFloat((zone[k] as? NSNumber)?.doubleValue ?? 0) }
        return flip(CGRect(x: inner.minX + z("x") * inner.width, y: inner.maxY - (z("y") + z("h")) * inner.height,
                           width: z("w") * inner.width, height: z("h") * inner.height).insetBy(dx: half, dy: half))
    }
}

func windows(owner: String) -> [[String: Any]] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]])
        .filter { ($0[kCGWindowOwnerName as String] as? String) == owner }
}

func targetBounds() -> CGRect? {
    guard let d = windows(owner: "MZTarget").first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: d)
}

let source = CGEventSource(stateID: .hidSystemState)

func mouse(_ type: CGEventType, _ p: CGPoint, _ flags: CGEventFlags = []) {
    let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
    e.flags = flags
    e.post(tap: .cghidEventTap)
}

func key(_ code: Int, _ down: Bool, _ flags: CGEventFlags = []) {
    let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)!
    e.flags = flags
    e.post(tap: .cghidEventTap)
}

/// Grab point on the title bar, clear of the traffic-light buttons.
func titleBar(_ r: CGRect) -> CGPoint { CGPoint(x: r.minX + 150, y: r.minY + 14) }

func drag(from a: CGPoint, to b: CGPoint, shift: Bool, screenshot: String? = nil) {
    let f: CGEventFlags = shift ? .maskShift : []
    mouse(.mouseMoved, a); usleep(150_000)
    if shift { key(kVK_Shift, true, .maskShift); usleep(50_000) }
    mouse(.leftMouseDown, a, f); usleep(200_000)
    for i in 1...40 {
        let t = CGFloat(i) / 40
        mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), f)
        usleep(15_000)
    }
    usleep(400_000)
    let overlays = windows(owner: "MacZones").filter { ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }
    print("   overlay visible mid-drag: \(!overlays.isEmpty)")
    if let screenshot, let id = overlays.first?[kCGWindowNumber as String] as? Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", "\(id)", screenshot]
        try? p.run()
        p.waitUntilExit()
    }
    mouse(.leftMouseUp, b, f)
    if shift { key(kVK_Shift, false) }
    usleep(700_000)
}

func near(_ a: CGRect?, _ b: CGRect) -> Bool {
    guard let a else { return false }
    return abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
}

func report(_ name: String, _ ok: Bool, _ detail: Any) {
    print(ok ? "PASS" : "FAIL", name, detail)
    if !ok { failures += 1 }
}

var failures = 0
let zones = expectedZones()
guard let start = targetBounds(), !zones.isEmpty else { print("no MZTarget window or no zones"); exit(1) }
let center = CGPoint(x: primary.visibleFrame.midX, y: primaryH - primary.visibleFrame.midY)
let centerZone = zones[zones.indices.min { zones[$0].distance(to: center) < zones[$1].distance(to: center) }!]

// 1) Shift-drag onto the screen center → window fills that zone.
drag(from: titleBar(start), to: center, shift: true,
     screenshot: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil)
let snapped = targetBounds()
report("shift-drag snaps into zone", near(snapped, centerZone), snapped as Any)

// 2) Plain drag out of the zone → original size restored.
if let snapped {
    drag(from: titleBar(snapped), to: CGPoint(x: center.x - 200, y: center.y), shift: false)
    let restored = targetBounds()
    let ok = restored.map { abs($0.width - start.width) < 3 && abs($0.height - start.height) < 3 } ?? false
    report("plain drag restores size", ok, restored as Any)
}

// 3) ⌃⌥⌘→ moves the focused window into a zone. Raw CGEvent key posts don't trigger Carbon
//    hotkeys reliably (and can leave modifiers stuck), so go through System Events.
let osa = Process()
osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
osa.arguments = ["-e", "tell application \"System Events\" to key code 124 using {control down, option down, command down}"]
try! osa.run()
osa.waitUntilExit()
usleep(700_000)
let moved = targetBounds()
report("hotkey moves window into a zone", zones.contains { near(moved, $0) }, moved as Any)

exit(failures == 0 ? 0 : 1)

extension CGRect {
    func distance(to p: CGPoint) -> CGFloat {
        let dx = Swift.max(minX - p.x, 0, p.x - maxX), dy = Swift.max(minY - p.y, 0, p.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
