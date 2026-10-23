import ServiceManagement
import SwiftUI

struct BehaviorView: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var key: ModifierKey { state.settings.activationKey }

    var body: some View {
        Form {
            Section {
                Toggle("Snap windows to zones", isOn: $state.settings.enabled)
            }

            Section("Activation") {
                Picker("Activation key", selection: $state.settings.activationKey) {
                    ForEach(ModifierKey.allCases.filter { $0 != .none }) { Text($0.label).tag($0) }
                }
                Picker("Show zones while dragging", selection: $state.settings.activationMode) {
                    Text("Only while holding \(key.label)").tag(ActivationMode.holdKey)
                    Text("Always — hold \(key.label) to hide them").tag(ActivationMode.always)
                }
                .pickerStyle(.radioGroup)
                Toggle("Right-click while dragging toggles zones", isOn: $state.settings.rightClickToggles)
                if key == .option {
                    Label("macOS uses ⌥ while dragging for its own window tiling. Pick another key, or turn off “Drag windows to screen edges to tile” in System Settings → Desktop & Dock.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Span zones key", selection: $state.settings.spanKey) {
                    ForEach(ModifierKey.allCases.filter { $0 != key }) { Text($0.label).tag($0) }
                }
                Toggle("Select neighbouring zones when the cursor is near their edge",
                       isOn: $state.settings.spanByProximity)
            } header: {
                Text("Multiple zones")
            } footer: {
                Text("Hold the span key while dragging across zones to snap a window over all of them.")
                    .foregroundStyle(.secondary)
            }

            Section("Windows") {
                Toggle("Restore original size when dragged out of a zone", isOn: $state.settings.restoreSizeOnUnsnap)
                Toggle("Show zones on all displays while dragging", isOn: $state.settings.showOnAllDisplays)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: state.settings.activationKey) { _, newKey in
            if state.settings.spanKey == newKey { state.settings.spanKey = .none }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct AppearanceView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Preview") {
                OverlayPreview(settings: state.settings)
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                HStack {
                    Spacer()
                    Button("Show on Screen") {
                        if let screen = NSScreen.at(NSEvent.mouseLocation) { state.flash(screen) }
                    }
                }
            }

            Section("Colors") {
                ColorPicker("Zone", selection: $state.settings.zoneColor.hexColor, supportsOpacity: false)
                ColorPicker("Highlight", selection: $state.settings.highlightColor.hexColor, supportsOpacity: false)
                ColorPicker("Border", selection: $state.settings.borderColor.hexColor, supportsOpacity: false)
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $state.settings.overlayOpacity, in: 0.1...0.9)
                        Text("\(Int(state.settings.overlayOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section("Zones") {
                LabeledContent("Spacing") {
                    HStack {
                        Slider(value: $state.settings.zoneSpacing, in: 0...40, step: 1)
                        Text("\(Int(state.settings.zoneSpacing)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Show zone numbers", isOn: $state.settings.showZoneNumbers)
                Toggle("Flash zones when switching layouts", isOn: $state.settings.flashOnLayoutChange)
            }

            Section {
                Button("Reset Appearance") {
                    let d = Settings()
                    state.settings.zoneColor = d.zoneColor
                    state.settings.highlightColor = d.highlightColor
                    state.settings.borderColor = d.borderColor
                    state.settings.overlayOpacity = d.overlayOpacity
                    state.settings.zoneSpacing = d.zoneSpacing
                    state.settings.showZoneNumbers = d.showZoneNumbers
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// SwiftUI approximation of the on-screen overlay, using the current colors.
private struct OverlayPreview: View {
    let settings: Settings

    var body: some View {
        let zone = Color(nsColor: NSColor(hex: settings.zoneColor) ?? .black)
        let highlight = Color(nsColor: NSColor(hex: settings.highlightColor) ?? .systemBlue)
        let border = Color(nsColor: NSColor(hex: settings.borderColor) ?? .white)
        let gap = max(2, settings.zoneSpacing / 3)

        ZStack {
            ScreenBackdrop(cornerRadius: 10)
            GeometryReader { geo in
                let side = (geo.size.width - gap * 2) * 0.25
                HStack(spacing: gap) {
                    tile(1, fill: zone.opacity(settings.overlayOpacity), stroke: border.opacity(0.4))
                        .frame(width: side)
                    tile(2, fill: highlight.opacity(min(1, settings.overlayOpacity + 0.2)), stroke: highlight, lit: true)
                    tile(3, fill: zone.opacity(settings.overlayOpacity), stroke: border.opacity(0.4))
                        .frame(width: side)
                }
            }
            .padding(gap)
        }
    }

    private func tile(_ n: Int, fill: Color, stroke: Color, lit: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(stroke, lineWidth: lit ? 3 : 1.5))
            .overlay {
                if settings.showZoneNumbers {
                    Text("\(n)").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                }
            }
    }
}

struct ShortcutsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("While dragging a window") {
                row([state.settings.activationKey.symbol, "drag"],
                    state.settings.activationMode == .holdKey ? "Show zones and snap on release" : "Hide zones")
                if state.settings.spanKey != .none {
                    row([state.settings.activationKey.symbol, state.settings.spanKey.symbol, "drag"],
                        "Span the window across several zones")
                }
                if state.settings.rightClickToggles {
                    row(["right-click"], "Toggle zones on/off for this drag")
                }
            }

            Section {
                Toggle("Enable keyboard shortcuts", isOn: $state.settings.shortcutsEnabled)
                Group {
                    row(["⌃", "⌥", "⌘", "→"], "Move focused window to next zone")
                    row(["⌃", "⌥", "⌘", "←"], "Move focused window to previous zone")
                    row(["⌃", "⌥", "⌘", "↓"], "Restore window's original size")
                    row(["⌃", "⌥", "⌘", "1–9"], "Switch layout on the display under the mouse")
                    row(["⌃", "⌥", "⌘", "`"], "Open layout editor")
                }
                .opacity(state.settings.shortcutsEnabled ? 1 : 0.4)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Moving past the last zone continues on the next display.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ keys: [String], _ action: String) -> some View {
        LabeledContent { Keycaps(keys: keys) } label: { Text(action) }
    }
}

struct GeneralView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmReset = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MacZones").font(.title2.weight(.semibold))
                        Text("Version \(version) · FancyZones-style window snapping").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if state.axTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") {
                            Permissions.prompt()
                            Permissions.openSettings()
                        }
                    }
                }
                if !state.axTrusted {
                    Text("Open System Settings → Privacy & Security → Accessibility and switch on MacZones. This page updates automatically once access is granted.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                LabeledContent("Configuration") {
                    Button("Show in Finder") {
                        state.save()
                        NSWorkspace.shared.activateFileViewerSelecting([AppState.configURL])
                    }
                }
                LabeledContent("Layouts") {
                    Button("Restore Default Layouts…") { confirmReset = true }
                }
            }

            Section {
                Button("Quit MacZones") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Replace all layouts with the defaults?", isPresented: $confirmReset) {
            Button("Restore Defaults", role: .destructive) { state.resetLayouts() }
        } message: {
            Text("Custom layouts will be deleted.")
        }
    }
}
