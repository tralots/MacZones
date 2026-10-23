import AppKit
import Combine

/// Menu bar icon + menu. The menu is rebuilt each time it opens so it always reflects current state.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let state: AppState
    private let open: (Pane?) -> Void
    private var bag = Set<AnyCancellable>()

    init(state: AppState, open: @escaping (Pane?) -> Void) {
        self.state = state
        self.open = open
        super.init()

        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1.fill", accessibilityDescription: "MacZones")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        state.$settings.map(\.enabled).removeDuplicates()
            .sink { [weak self] enabled in self?.item.button?.appearsDisabled = !enabled }
            .store(in: &bag)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !state.axTrusted {
            let warn = menu.addItem(withTitle: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
            warn.target = self
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(.separator())
        }

        let toggle = menu.addItem(withTitle: "Snap Windows (hold \(state.settings.activationKey.symbol) while dragging)",
                                  action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = state.settings.enabled ? .on : .off
        menu.addItem(.separator())

        let screens = NSScreen.screens
        for screen in screens {
            menu.addItem(.sectionHeader(title: screens.count > 1 ? screen.localizedName : "Layout"))
            let active = state.layout(for: screen)?.id
            for (i, layout) in state.layouts.enumerated() {
                let entry = menu.addItem(withTitle: layout.name, action: #selector(pickLayout(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = LayoutChoice(screenID: screen.stableID, layoutID: layout.id)
                entry.state = layout.id == active ? .on : .off
                entry.image = Self.thumbnail(for: layout)
                if screens.count == 1, i < 9, state.settings.shortcutsEnabled {
                    entry.keyEquivalent = "\(i + 1)"
                    entry.keyEquivalentModifierMask = [.control, .option, .command]
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit Layouts…", action: #selector(editLayouts), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacZones", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private final class LayoutChoice: NSObject {
        let screenID: String
        let layoutID: UUID
        init(screenID: String, layoutID: UUID) {
            self.screenID = screenID
            self.layoutID = layoutID
        }
    }

    @objc private func pickLayout(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? LayoutChoice,
              let screen = NSScreen.with(id: choice.screenID) else { return }
        state.assign(choice.layoutID, to: screen)
    }

    @objc private func toggleEnabled() { state.settings.enabled.toggle() }
    @objc private func grantAccess() { Permissions.prompt(); Permissions.openSettings(); open(.general) }
    @objc private func editLayouts() { open(.layouts) }
    @objc private func openSettings() { open(.behavior) }

    /// Small template image of a layout's zones for menu items.
    static func thumbnail(for layout: ZoneLayout) -> NSImage {
        let size = NSSize(width: 24, height: 15)
        let image = NSImage(size: size, flipped: true) { bounds in
            let frame = bounds.insetBy(dx: 0.5, dy: 0.5)
            let outline = NSBezierPath(roundedRect: frame, xRadius: 2.5, yRadius: 2.5)
            NSColor.black.withAlphaComponent(0.5).setStroke()
            outline.lineWidth = 1
            outline.stroke()
            let inner = frame.insetBy(dx: 1.5, dy: 1.5)
            for zone in layout.zones {
                let r = CGRect(x: inner.minX + zone.x * inner.width, y: inner.minY + zone.y * inner.height,
                               width: zone.w * inner.width, height: zone.h * inner.height).insetBy(dx: 0.6, dy: 0.6)
                let path = NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1)
                NSColor.black.withAlphaComponent(0.55).setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
