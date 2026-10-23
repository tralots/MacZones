import SwiftUI

/// Wallpaper-ish backdrop used behind layout previews and the editor canvas.
struct ScreenBackdrop: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.13, blue: 0.36),
                                          Color(red: 0.05, green: 0.27, blue: 0.48)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// Miniature rendering of a layout's zones.
struct LayoutPreview: View {
    let zones: [Zone]
    var active = false
    var gap: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let inner = CGRect(origin: .zero, size: geo.size).insetBy(dx: gap, dy: gap)
            ZStack(alignment: .topLeading) {
                ScreenBackdrop()
                ForEach(Array(zones.enumerated()), id: \.element.id) { i, zone in
                    let r = CGRect(x: inner.minX + zone.x * inner.width, y: inner.minY + zone.y * inner.height,
                                   width: zone.w * inner.width, height: zone.h * inner.height)
                        .insetBy(dx: gap / 2, dy: gap / 2)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(active ? 0.7 : 0.35), lineWidth: 1))
                        .overlay(Text("\(i + 1)")
                            .font(.system(size: max(8, min(r.height * 0.35, 15)), weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85)))
                        .frame(width: max(r.width, 0), height: max(r.height, 0))
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }
}

struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access needed").font(.headline)
                Text("MacZones moves other apps' windows through the Accessibility API. Enable MacZones under Privacy & Security → Accessibility.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings") {
                Permissions.prompt()
                Permissions.openSettings()
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.35)))
    }
}

/// Renders key symbols like ⌃ ⌥ ⌘ → as little keycaps.
struct Keycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
            }
        }
    }
}

extension Binding where Value == String {
    /// Bridges a "#RRGGBB" string to a SwiftUI Color for ColorPicker.
    var hexColor: Binding<Color> {
        Binding<Color>(
            get: { Color(nsColor: NSColor(hex: wrappedValue) ?? .black) },
            set: { wrappedValue = NSColor($0).hexString }
        )
    }
}
