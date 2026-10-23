import SwiftUI

/// Canvas editor: drag zones to move, drag handles to resize, split/add/delete, start from templates.
struct LayoutEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State var layout: ZoneLayout
    let isNew: Bool
    /// Visible frame size of the display being edited, for aspect ratio and pixel labels.
    let screenSize: CGSize

    @State private var selection: UUID?
    @State private var snapToGrid = true
    @State private var dragStart: CGRect?

    private let gridDivisions = 24.0
    private let minSize = 0.05

    private var aspect: CGFloat { screenSize.width / max(screenSize.height, 1) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
                .padding(28)
            Divider()
            footer
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 620, idealHeight: 700)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Layout name", text: $layout.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Spacer()

            Menu {
                ForEach(LayoutTemplate.allCases) { template in
                    if template.counts.count > 1 {
                        Menu {
                            ForEach(Array(template.counts), id: \.self) { n in
                                Button("\(n) zones") { applyTemplate(template, count: n) }
                            }
                        } label: {
                            Label(template.title, systemImage: template.symbol)
                        }
                    } else {
                        Button { applyTemplate(template, count: template.counts.lowerBound) } label: {
                            Label(template.title, systemImage: template.symbol)
                        }
                    }
                }
            } label: {
                Label("Template", systemImage: "square.grid.3x3.square")
            }
            .fixedSize()

            Divider().frame(height: 20)

            Button(action: addZone) { Label("Add Zone", systemImage: "plus.rectangle") }
            Button { split(horizontally: true) } label: { Label("Split Left/Right", systemImage: "rectangle.split.2x1") }
                .disabled(selection == nil)
            Button { split(horizontally: false) } label: { Label("Split Top/Bottom", systemImage: "rectangle.split.1x2") }
                .disabled(selection == nil)
            Button(action: deleteSelected) { Label("Delete Zone", systemImage: "trash") }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selection == nil)

            Divider().frame(height: 20)

            Toggle(isOn: $snapToGrid) { Label("Snap to Grid", systemImage: "grid") }
                .toggleStyle(.button)
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text("Drag a zone to move it · drag its handles to resize · overlapping zones are fine (smallest wins)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Create Layout" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(layout.zones.isEmpty)
        }
        .padding(16)
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let size = fitted(in: geo.size)
            ZStack(alignment: .topLeading) {
                ScreenBackdrop(cornerRadius: 12)
                    .onTapGesture { selection = nil }
                if snapToGrid { gridLines(size) }
                ForEach(Array(layout.zones.enumerated()), id: \.element.id) { i, zone in
                    zoneView(zone, number: i + 1, canvas: size)
                        .zIndex(zone.id == selection ? 1 : 0)
                }
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: "canvas")
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func fitted(in available: CGSize) -> CGSize {
        let width = min(available.width, available.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    private func gridLines(_ size: CGSize) -> some View {
        Canvas { ctx, _ in
            for i in 1..<Int(gridDivisions) {
                let t = CGFloat(i) / gridDivisions
                let major = i % 6 == 0
                var path = Path()
                path.move(to: CGPoint(x: t * size.width, y: 0))
                path.addLine(to: CGPoint(x: t * size.width, y: size.height))
                path.move(to: CGPoint(x: 0, y: t * size.height))
                path.addLine(to: CGPoint(x: size.width, y: t * size.height))
                ctx.stroke(path, with: .color(.white.opacity(major ? 0.12 : 0.05)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func zoneView(_ zone: Zone, number: Int, canvas: CGSize) -> some View {
        let r = CGRect(x: zone.x * canvas.width, y: zone.y * canvas.height,
                       width: zone.w * canvas.width, height: zone.h * canvas.height)
        let selected = zone.id == selection
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.14))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.45), lineWidth: selected ? 2 : 1)
            VStack(spacing: 2) {
                Text("\(number)")
                    .font(.system(size: min(32, max(12, r.height * 0.25)), weight: .bold, design: .rounded))
                if r.height > 70 {
                    Text("\(Int(zone.w * screenSize.width)) × \(Int(zone.h * screenSize.height))")
                        .font(.caption.monospacedDigit())
                        .opacity(0.75)
                }
            }
            .foregroundStyle(.white)
            .allowsHitTesting(false)
        }
        .frame(width: r.width, height: r.height)
        .overlay { if selected { handles(for: zone, canvas: canvas, size: r.size) } }
        .contentShape(Rectangle())
        .onTapGesture { selection = zone.id }
        .gesture(moveGesture(zone.id, canvas: canvas))
        .position(x: r.midX, y: r.midY)
    }

    // MARK: - Gestures

    private func moveGesture(_ id: UUID, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard let i = index(of: id) else { return }
                if dragStart == nil {
                    dragStart = layout.zones[i].rect
                    selection = id
                }
                guard let start = dragStart else { return }
                var x = start.minX + value.translation.width / canvas.width
                var y = start.minY + value.translation.height / canvas.height
                x = snap(x)
                y = snap(y)
                x = min(max(0, x), 1 - start.width)
                y = min(max(0, y), 1 - start.height)
                layout.zones[i].rect = CGRect(x: x, y: y, width: start.width, height: start.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Handle positions as (dx, dy): -1 = min edge, 1 = max edge, 0 = middle.
    private static let handlePoints: [(Int, Int)] = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)]

    private func handles(for zone: Zone, canvas: CGSize, size: CGSize) -> some View {
        ZStack {
            ForEach(Array(Self.handlePoints.enumerated()), id: \.offset) { _, handle in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                    .frame(width: 11, height: 11)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .position(x: CGFloat(handle.0 + 1) / 2 * size.width, y: CGFloat(handle.1 + 1) / 2 * size.height)
                    .gesture(resizeGesture(zone.id, handle: handle, canvas: canvas))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func resizeGesture(_ id: UUID, handle: (Int, Int), canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard let i = index(of: id) else { return }
                if dragStart == nil { dragStart = layout.zones[i].rect }
                guard let start = dragStart else { return }
                let tx = value.translation.width / canvas.width
                let ty = value.translation.height / canvas.height
                var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
                if handle.0 == -1 { minX = min(max(0, snap(start.minX + tx)), maxX - minSize) }
                if handle.0 == 1 { maxX = max(min(1, snap(start.maxX + tx)), minX + minSize) }
                if handle.1 == -1 { minY = min(max(0, snap(start.minY + ty)), maxY - minSize) }
                if handle.1 == 1 { maxY = max(min(1, snap(start.maxY + ty)), minY + minSize) }
                layout.zones[i].rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: - Actions

    private func snap(_ v: Double) -> Double {
        snapToGrid ? (v * gridDivisions).rounded() / gridDivisions : v
    }

    private func index(of id: UUID) -> Int? {
        layout.zones.firstIndex { $0.id == id }
    }

    private func applyTemplate(_ template: LayoutTemplate, count: Int) {
        layout.zones = template.zones(count: count)
        selection = nil
    }

    private func addZone() {
        let zone = layout.zones.isEmpty
            ? Zone(x: 0, y: 0, w: 1, h: 1)
            : Zone(x: 0.25, y: 0.25, w: 0.5, h: 0.5)
        layout.zones.append(zone)
        selection = zone.id
    }

    private func split(horizontally: Bool) {
        guard let id = selection, let i = index(of: id) else { return }
        let r = layout.zones[i].rect
        let parts = horizontally
            ? r.divided(atDistance: r.width / 2, from: .minXEdge)
            : r.divided(atDistance: r.height / 2, from: .minYEdge)
        layout.zones[i].rect = parts.slice
        layout.zones.insert(Zone(parts.remainder), at: i + 1)
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        layout.zones.removeAll { $0.id == id }
        selection = nil
    }

    private func save() {
        if layout.name.trimmingCharacters(in: .whitespaces).isEmpty { layout.name = "Untitled" }
        state.upsert(layout)
        dismiss()
    }
}
