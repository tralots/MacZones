import XCTest
@testable import MacZones

final class ZoneGeometryTests: XCTestCase {
    func testTemplatesTileTheScreen() {
        for template in LayoutTemplate.allCases where template != .blank {
            for n in template.counts {
                let zones = template.zones(count: n)
                XCTAssertEqual(zones.count, n, "\(template) \(n)")
                let area = zones.reduce(0) { $0 + $1.w * $1.h }
                XCTAssertEqual(area, 1, accuracy: 1e-9, "\(template) \(n) should cover the screen exactly once")
                for z in zones {
                    XCTAssertTrue(z.x >= 0 && z.y >= 0 && z.x + z.w <= 1 + 1e-9 && z.y + z.h <= 1 + 1e-9)
                }
            }
        }
    }

    func testRectsUseTopLeftZonesAndSpacing() {
        let halves = LayoutTemplate.rows.zones(count: 2)
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rects = ZoneGeometry.rects(for: halves, in: area, spacing: 10)
        // Zone 1 is the top row → higher Cocoa y.
        XCTAssertGreaterThan(rects[0].minY, rects[1].minY)
        XCTAssertEqual(rects[0].minX, 10)
        XCTAssertEqual(rects[0].maxY, 790)
        XCTAssertEqual(rects[1].minY, 10)
        XCTAssertEqual(rects[0].minY - rects[1].maxY, 10) // gap between zones
    }

    func testHitTestPrefersSmallestContainingZoneThenNearest() {
        let rects = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 25, y: 25, width: 50, height: 50)]
        XCTAssertEqual(ZoneGeometry.hitTest(CGPoint(x: 50, y: 50), in: rects), 1)
        XCTAssertEqual(ZoneGeometry.hitTest(CGPoint(x: 5, y: 5), in: rects), 0)
        let apart = [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 100, y: 0, width: 10, height: 10)]
        XCTAssertEqual(ZoneGeometry.hitTest(CGPoint(x: 80, y: 5), in: apart), 1)
    }

    func testSpanCoversZonesBetweenAnchorAndCursor() {
        let rects = ZoneGeometry.rects(for: LayoutTemplate.columns.zones(count: 4),
                                       in: CGRect(x: 0, y: 0, width: 400, height: 100), spacing: 0)
        XCTAssertEqual(ZoneGeometry.span(from: 0, to: 2, in: rects), [0, 1, 2])
        XCTAssertEqual(ZoneGeometry.span(from: 3, to: 3, in: rects), [3])
    }

    func testCoordinateFlipIsSelfInverse() {
        let r = CGRect(x: 12, y: 34, width: 560, height: 78)
        XCTAssertEqual(Coords.flip(Coords.flip(r)), r)
    }

    func testSettingsDecodeToleratesMissingAndUnknownValues() throws {
        let json = #"{"activationKey":"hyper","zoneSpacing":20}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(s.activationKey, .shift) // unknown value → default
        XCTAssertEqual(s.zoneSpacing, 20)
        XCTAssertTrue(s.enabled)
    }
}
