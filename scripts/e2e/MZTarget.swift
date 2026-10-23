import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let w = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 640, height: 420),
                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
w.title = "MZTarget"
w.level = .floating
w.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
DispatchQueue.main.asyncAfter(deadline: .now() + 40) { exit(0) }
app.run()
