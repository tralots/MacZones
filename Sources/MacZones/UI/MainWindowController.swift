import AppKit
import SwiftUI

/// The settings window. While it is open the app becomes a regular app (Dock icon, ⌘-Tab, main menu).
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show(_ pane: Pane?) {
        if let pane { state.pane = pane }
        if window == nil {
            let host = NSHostingController(rootView: MainView().environmentObject(state))
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.title = "MacZones"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 960, height: 660))
            window.minSize = NSSize(width: 780, height: 520)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("MacZonesMainWindow")
            if !window.setFrameUsingName("MacZonesMainWindow") { window.center() }
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
