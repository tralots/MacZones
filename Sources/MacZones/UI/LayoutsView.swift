import SwiftUI

struct EditorTarget: Identifiable {
    var layout: ZoneLayout
    var isNew: Bool
    var id: UUID { layout.id }
}

struct LayoutsView: View {
    @EnvironmentObject private var state: AppState
    @State private var screenID = NSScreen.at(NSEvent.mouseLocation)?.stableID ?? ""
    @State private var editing: EditorTarget?
    @State private var pendingDelete: ZoneLayout?

    private var screen: NSScreen? { NSScreen.with(id: screenID) ?? NSScreen.screens.first }
    private var screenSize: CGSize { screen?.visibleFrame.size ?? CGSize(width: 16, height: 10) }
    private var aspect: CGFloat { screenSize.width / max(screenSize.height, 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !state.axTrusted { PermissionBanner() }
                if NSScreen.screens.count > 1 { displayPicker }
                grid
            }
            .padding(24)
        }
        .onAppear {
            // `--args -MZEditFirst YES` opens the editor on the first layout (screenshots/debugging).
            if UserDefaults.standard.bool(forKey: "MZEditFirst"), let first = state.layouts.first {
                editing = EditorTarget(layout: first, isNew: false)
            }
        }
        .sheet(item: $editing) { target in
            LayoutEditorView(layout: target.layout, isNew: target.isNew, screenSize: screenSize)
                .environmentObject(state)
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: deleteBinding) {
            Button("Delete", role: .destructive) {
                if let layout = pendingDelete { state.delete(layout) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Choose a layout for \(screen?.localizedName ?? "this display")")
                .font(.title2.weight(.semibold))
            Text("Drag any window while holding \(state.settings.activationKey.label) and drop it on a zone. Right-click a layout to edit it.")
                .foregroundStyle(.secondary)
        }
    }

    private var displayPicker: some View {
        Picker("Display", selection: $screenID) {
            ForEach(NSScreen.screens, id: \.stableID) { screen in
                Text(screen.localizedName).tag(screen.stableID)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 480)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)], spacing: 16) {
            ForEach(Array(state.layouts.enumerated()), id: \.element.id) { i, layout in
                LayoutCard(layout: layout, number: i + 1, aspect: aspect,
                           active: screen.flatMap { state.layout(for: $0)?.id } == layout.id,
                           showShortcut: state.settings.shortcutsEnabled)
                    .onTapGesture {
                        if let screen { state.assign(layout.id, to: screen) }
                    }
                    .contextMenu {
                        Button("Edit…") { editing = EditorTarget(layout: layout, isNew: false) }
                        Button("Duplicate") { state.duplicate(layout) }
                        Divider()
                        Button("Move Earlier") { state.move(layout, by: -1) }.disabled(i == 0)
                        Button("Move Later") { state.move(layout, by: 1) }.disabled(i == state.layouts.count - 1)
                        Divider()
                        Button("Delete…", role: .destructive) { pendingDelete = layout }
                            .disabled(state.layouts.count < 2)
                    }
            }
            NewLayoutCard(aspect: aspect)
                .onTapGesture {
                    let layout = ZoneLayout(name: "Custom \(state.layouts.count + 1)",
                                            zones: LayoutTemplate.columns.zones(count: 2))
                    editing = EditorTarget(layout: layout, isNew: true)
                }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}

private struct LayoutCard: View {
    let layout: ZoneLayout
    let number: Int
    let aspect: CGFloat
    let active: Bool
    let showShortcut: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayoutPreview(zones: layout.zones, active: active)
                .aspectRatio(aspect, contentMode: .fit)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.name).font(.headline).lineLimit(1)
                    Text("\(layout.zones.count) zone\(layout.zones.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                } else if showShortcut, number <= 9 {
                    Text("⌃⌥⌘\(number)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(active ? Color.accentColor : Color.primary.opacity(hovering ? 0.25 : 0.08),
                          lineWidth: active ? 2 : 1))
        .shadow(color: .black.opacity(hovering ? 0.15 : 0.05), radius: hovering ? 8 : 3, y: 2)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.spring(duration: 0.2), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct NewLayoutCard: View {
    let aspect: CGFloat
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(.secondary)
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(Image(systemName: "plus").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text("New Layout").font(.headline)
                Text("Start from a template").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.05 : 0.02)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
