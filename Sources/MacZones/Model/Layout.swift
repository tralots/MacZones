import Foundation
import CoreGraphics

/// A zone in normalized coordinates (0…1) relative to a display's visible frame. Origin is top-left.
struct Zone: Codable, Hashable, Identifiable {
    var id = UUID()
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    init(id: UUID = UUID(), x: Double, y: Double, w: Double, h: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
    }

    var rect: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set {
            x = newValue.minX
            y = newValue.minY
            w = newValue.width
            h = newValue.height
        }
    }
}

struct ZoneLayout: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var zones: [Zone]
}

/// Generators for common layouts. Templates only produce zones; every layout is freely editable afterwards.
enum LayoutTemplate: String, CaseIterable, Identifiable {
    case columns, rows, grid, priorityGrid, mainStack, blank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .columns: "Columns"
        case .rows: "Rows"
        case .grid: "Grid"
        case .priorityGrid: "Priority Grid"
        case .mainStack: "Main + Stack"
        case .blank: "Blank"
        }
    }

    var symbol: String {
        switch self {
        case .columns: "rectangle.split.3x1"
        case .rows: "rectangle.split.1x2"
        case .grid: "rectangle.split.2x2"
        case .priorityGrid: "rectangle.center.inset.filled"
        case .mainStack: "rectangle.lefthalf.inset.filled"
        case .blank: "rectangle.dashed"
        }
    }

    var counts: ClosedRange<Int> {
        switch self {
        case .columns, .rows: 1...8
        case .grid: 2...16
        case .priorityGrid: 1...5
        case .mainStack: 2...6
        case .blank: 0...0
        }
    }

    func zones(count n: Int) -> [Zone] {
        let n = min(max(n, counts.lowerBound), counts.upperBound)
        switch self {
        case .columns:
            return (0..<n).map { Zone(x: Double($0) / Double(n), y: 0, w: 1 / Double(n), h: 1) }
        case .rows:
            return (0..<n).map { Zone(x: 0, y: Double($0) / Double(n), w: 1, h: 1 / Double(n)) }
        case .grid:
            let cols = Int(Double(n).squareRoot().rounded(.up))
            let rows = Int((Double(n) / Double(cols)).rounded(.up))
            var out: [Zone] = []
            for r in 0..<rows {
                let inRow = min(cols, n - r * cols)
                for c in 0..<inRow {
                    out.append(Zone(x: Double(c) / Double(inRow), y: Double(r) / Double(rows),
                                    w: 1 / Double(inRow), h: 1 / Double(rows)))
                }
            }
            return out
        case .priorityGrid:
            switch n {
            case 1: return [Zone(x: 0, y: 0, w: 1, h: 1)]
            case 2: return [Zone(x: 0, y: 0, w: 2 / 3, h: 1), Zone(x: 2 / 3, y: 0, w: 1 / 3, h: 1)]
            case 3: return [Zone(x: 0, y: 0, w: 0.25, h: 1), Zone(x: 0.25, y: 0, w: 0.5, h: 1),
                            Zone(x: 0.75, y: 0, w: 0.25, h: 1)]
            case 4: return [Zone(x: 0, y: 0, w: 0.25, h: 1), Zone(x: 0.25, y: 0, w: 0.5, h: 1),
                            Zone(x: 0.75, y: 0, w: 0.25, h: 0.5), Zone(x: 0.75, y: 0.5, w: 0.25, h: 0.5)]
            default: return [Zone(x: 0, y: 0, w: 0.25, h: 0.5), Zone(x: 0, y: 0.5, w: 0.25, h: 0.5),
                             Zone(x: 0.25, y: 0, w: 0.5, h: 1),
                             Zone(x: 0.75, y: 0, w: 0.25, h: 0.5), Zone(x: 0.75, y: 0.5, w: 0.25, h: 0.5)]
            }
        case .mainStack:
            let stack = n - 1
            return [Zone(x: 0, y: 0, w: 0.6, h: 1)]
                + (0..<stack).map { Zone(x: 0.6, y: Double($0) / Double(stack), w: 0.4, h: 1 / Double(stack)) }
        case .blank:
            return []
        }
    }
}

enum DefaultLayouts {
    static func make() -> [ZoneLayout] {
        [
            ZoneLayout(name: "Priority Grid", zones: LayoutTemplate.priorityGrid.zones(count: 3)),
            ZoneLayout(name: "Halves", zones: LayoutTemplate.columns.zones(count: 2)),
            ZoneLayout(name: "Thirds", zones: LayoutTemplate.columns.zones(count: 3)),
            ZoneLayout(name: "Grid", zones: LayoutTemplate.grid.zones(count: 4)),
            ZoneLayout(name: "Main + Stack", zones: LayoutTemplate.mainStack.zones(count: 3)),
            ZoneLayout(name: "Sixths", zones: LayoutTemplate.grid.zones(count: 6)),
            ZoneLayout(name: "Rows", zones: LayoutTemplate.rows.zones(count: 2)),
        ]
    }
}

enum ZoneGeometry {
    /// Screen rects (Cocoa global coordinates) for zones laid out inside `area`.
    /// `spacing` is applied between zones and as an outer margin.
    static func rects(for zones: [Zone], in area: CGRect, spacing: CGFloat) -> [CGRect] {
        let half = max(spacing, 0) / 2
        let inner = area.insetBy(dx: half, dy: half)
        return zones.map { z in
            CGRect(x: inner.minX + z.x * inner.width,
                   y: inner.maxY - (z.y + z.h) * inner.height,
                   width: z.w * inner.width,
                   height: z.h * inner.height)
                .insetBy(dx: half, dy: half)
                .roundedToPixels
        }
    }

    /// Zone under `point`: the smallest zone containing it (so nested/overlapping zones work), else the nearest one.
    static func hitTest(_ point: CGPoint, in rects: [CGRect]) -> Int? {
        let containing = rects.indices.filter { rects[$0].contains(point) }
        if let best = containing.min(by: { rects[$0].area < rects[$1].area }) { return best }
        return rects.indices.min { rects[$0].distance(to: point) < rects[$1].distance(to: point) }
    }

    /// Zones covered by the bounding box of two zones (multi-zone span).
    static func span(from a: Int, to b: Int, in rects: [CGRect]) -> Set<Int> {
        let box = rects[a].union(rects[b])
        return Set(rects.indices.filter { i in
            let overlap = rects[i].intersection(box)
            return !overlap.isNull && overlap.area >= rects[i].area * 0.5
        }).union([a, b])
    }

    /// `base` plus every zone within `distance` of the point.
    static func proximity(_ point: CGPoint, base: Int, in rects: [CGRect], distance: CGFloat) -> Set<Int> {
        Set(rects.indices.filter { rects[$0].distance(to: point) <= distance }).union([base])
    }
}
