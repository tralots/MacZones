import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState.shared
    private lazy var overlay = OverlayController(state: state)
    private lazy var snapper = SnapController(state: state, overlay: overlay)
    private lazy var mainWindow = MainWindowController(state: state)
    private var statusItem: StatusItemController?
    private var permissionTimer: Timer?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        statusItem = StatusItemController(state: state) { [weak self] pane in self?.mainWindow.show(pane) }

        snapper.start()

        state.$settings.map(\.shortcutsEnabled).removeDuplicates()
            .sink { [weak self] enabled in self?.registerHotKeys(enabled) }
            .store(in: &bag)

        state.flashRequests
            .sink { [weak self] id in
                if let screen = NSScreen.with(id: id) { self?.overlay.flash(screen) }
            }
            .store(in: &bag)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.overlay.screensChanged() }
        }

        // Trust can be granted or revoked at any time in System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermission() }
        }

        // `open MacZones.app --args -MZPane layouts` opens a specific pane (handy for screenshots/debugging).
        if let pane = UserDefaults.standard.string(forKey: "MZPane").flatMap(Pane.init(rawValue:)) {
            mainWindow.show(pane)
        } else if !state.axTrusted {
            Permissions.prompt()
            mainWindow.show(.general)
        } else if state.isFirstLaunch {
            mainWindow.show(.layouts)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show(nil)
        return true
    }

    private func checkPermission() {
        let trusted = Permissions.isTrusted
        guard trusted != state.axTrusted else { return }
        state.axTrusted = trusted
        if trusted { snapper.start() } // re-install monitors now that key events are allowed
    }

    private func registerHotKeys(_ enabled: Bool) {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        guard enabled else { return }
        center.register(keyCode: kVK_LeftArrow) { [weak self] in self?.snapper.moveFocusedWindow(by: -1) }
        center.register(keyCode: kVK_RightArrow) { [weak self] in self?.snapper.moveFocusedWindow(by: 1) }
        center.register(keyCode: kVK_DownArrow) { [weak self] in self?.snapper.restoreFocusedWindow() }
        center.register(keyCode: kVK_ANSI_Grave) { [weak self] in self?.mainWindow.show(.layouts) }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (i, key) in digits.enumerated() {
            center.register(keyCode: key) { [weak self] in self?.snapper.applyLayout(number: i + 1) }
        }
    }

    // MARK: - Main menu (only visible while the settings window is open)

    @objc private func openSettings() {
        mainWindow.show(.behavior)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MacZones",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MacZones", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit MacZones", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "MacZones")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit, title: "Edit")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: window, title: "Window")
        NSApp.windowsMenu = window

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
