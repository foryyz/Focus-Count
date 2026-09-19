import XCTest
import FocusCountCore
@testable import FocusCount

final class MarkerPointLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var start: Date { Date(timeIntervalSince1970: 0) }
    func testCoincidentRecordsArePlacedSideBySideWithoutChangingTime() {
        let events = (0..<3).map { _ in TimeEvent(kind: "a", occurredAt: start.addingTimeInterval(12 * 3600 + 30 * 60)) }
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 1, width: 200, calendar: calendar)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { !$0.grouped && $0.events.count == 1 })
        XCTAssertEqual(Set(items.map(\.x)).count, 3)
        XCTAssertTrue(items.allSatisfy { $0.y == 375 })
    }
    func testCrowdedRecordsAggregateWithoutLosingAnyEvent() {
        let events = (0..<10).map { _ in TimeEvent(kind: "a", occurredAt: start.addingTimeInterval(3600)) }
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 7, width: 560, calendar: calendar)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].grouped)
        XCTAssertEqual(Set(items.flatMap(\.events).map(\.id)), Set(events.map(\.id)))
        let expanded = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 1, width: 560, calendar: calendar)
        XCTAssertEqual(expanded.count, 10)
    }
    func testTimeSlotsAndVisibleDateFiltering() {
        var deleted = TimeEvent(kind: "a", occurredAt: start); deleted.deletedAt = start
        let events = [TimeEvent(kind: "a", occurredAt: start), TimeEvent(kind: "b", occurredAt: start.addingTimeInterval(23 * 3600 + 59 * 60)), TimeEvent(kind: "c", occurredAt: start.addingTimeInterval(86400)), deleted]
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 1, width: 200, calendar: calendar)
        XCTAssertEqual(items.flatMap(\.events).count, 2)
        XCTAssertEqual(items.map(\.anchorY).min(), 0)
        XCTAssertEqual(items.map(\.anchorY).max()!, 719.5, accuracy: 0.001)
    }
    func testCrowdingGroupsByKindAndSizesByCount() {
        let time = start.addingTimeInterval(12 * 3600)
        let events = (0..<5).map { _ in TimeEvent(kind: "健身", occurredAt: time) } + (0..<2).map { _ in TimeEvent(kind: "冥想", occurredAt: time) }
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 4, width: 560, hourHeight: 12, calendar: calendar)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { Set($0.events.map(\.kind)).count == 1 })
        let large = items.first { $0.events.count == 5 }!
        let small = items.first { $0.events.count == 2 }!
        XCTAssertGreaterThan(large.diameter, small.diameter)
        XCTAssertEqual(Set(items.flatMap(\.events).map(\.id)), Set(events.map(\.id)))
        XCTAssertTrue(abs(large.x - small.x) >= (large.diameter + small.diameter) / 2 || abs(large.y - small.y) >= (large.diameter + small.diameter) / 2)
    }
    func testSeparateRecordsArePreferredWhenTheyFit() {
        let events = (0..<4).map { _ in TimeEvent(kind: "same", occurredAt: start.addingTimeInterval(12 * 3600)) }
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 4, width: 560, hourHeight: 12, calendar: calendar)
        XCTAssertEqual(items.count, 4)
        XCTAssertTrue(items.allSatisfy { !$0.grouped })
    }

}
