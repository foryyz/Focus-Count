import XCTest
import SwiftUI
import AppKit
import FocusCountCore
@testable import FocusCount

final class ShareLabelTests: XCTestCase {
    func testSectorFitUsesGeometryInsteadOfPercentage() {
        // An 8% wedge can contain a short two-line label at this radius.
        XCTAssertTrue(ShareLabelGeometry.fits(CGRect(x: 21, y: -167, width: 28, height: 25), start: 0, end: 0.08, radius: 200, hole: 0))
        XCTAssertFalse(ShareLabelGeometry.fits(CGRect(x: -10, y: -167, width: 28, height: 25), start: 0, end: 0.08, radius: 200, hole: 0))
        XCTAssertFalse(ShareLabelGeometry.fits(CGRect(x: 180, y: 0, width: 30, height: 25), start: 0, end: 1, radius: 200, hole: 0))
    }
    func testRingKeepsTextOutsideCenterAndInsideArc() {
        XCTAssertTrue(ShareLabelGeometry.fits(CGRect(x: 155, y: -14, width: 28, height: 28), start: 0, end: 0.5, radius: 200, hole: 0.7))
        XCTAssertFalse(ShareLabelGeometry.fits(CGRect(x: 125, y: -14, width: 28, height: 28), start: 0, end: 0.5, radius: 200, hole: 0.7))
        XCTAssertFalse(ShareLabelGeometry.fits(CGRect(x: -5, y: -175, width: 10, height: 350), start: 0.01, end: 0.99, radius: 200, hole: 0))
    }
    @MainActor func testRenderShareCharts() throws {
        let values: [(String, Double, Color)] = [("学习", 44, .blue), ("项目开发", 27, .purple), ("健身", 15, .green), ("阅读", 8, .orange), ("很长的活动名称测试", 5, .yellow), ("冥想", 1, .pink)]
        let now = Date()
        let groups = values.map { FocusBreakdown(name: $0.0, records: [StudySession(startedAt: now, endedAt: now, activeSeconds: $0.1 * 60, subject: $0.0, focus: "A")]) }
        for width in [400.0, 560] {
            for pie in [true, false] {
                for dark in [false, true] {
                    let chart = FocusShareChart(items: groups, activityCount: groups.count, pie: pie) { group in values.first { $0.0 == group.name }!.2 }
                        .frame(width: width, height: 340).padding(20)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: chart)
                    renderer.scale = 2
                    let data = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: "/private/tmp/fc-share-\(Int(width))-\(pie ? "pie" : "ring")-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
