import XCTest
import FocusCountCore
@testable import FocusCount

final class MarkerOverviewTests: XCTestCase {
    private var cal: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func testThirtyDaysRetainEmptyDaysAndSeparateKinds() {
        let start = date(2026, 8, 1), end = date(2026, 8, 31)
        let events = [TimeEvent(kind: "Gym", occurredAt: start), TimeEvent(kind: "gym", occurredAt: start), TimeEvent(kind: "冥想", occurredAt: start)]
        let data = MarkerOverviewData(events: events, start: start, end: end, granularity: .automatic, now: end, calendar: cal)
        XCTAssertEqual(data.granularity, .day)
        XCTAssertEqual(data.buckets.count, 30)
        XCTAssertEqual(data.cells.count, 2)
        XCTAssertEqual(data.cells.first { $0.kind == "gym" }?.events.count, 2)
        XCTAssertEqual(Set(data.cells.flatMap(\.events).map(\.id)), Set(events.map(\.id)))
    }
    func testWeekUsesMondayAndHalfOpenBoundaries() {
        let start = date(2026, 9, 14), boundary = date(2026, 9, 21), end = date(2026, 9, 28)
        let events = [TimeEvent(kind: "a", occurredAt: boundary.addingTimeInterval(-1)), TimeEvent(kind: "a", occurredAt: boundary), TimeEvent(kind: "a", occurredAt: end)]
        let data = MarkerOverviewData(events: events, start: start, end: end, granularity: .week, now: end, calendar: cal)
        XCTAssertEqual(data.buckets.map(\.start), [start, boundary])
        XCTAssertEqual(data.cells.map { $0.events.count }, [1, 1])
        XCTAssertTrue(data.buckets.allSatisfy { !$0.partial })
    }
    func testPartialMonthExcludesDeletedAndFutureRecords() {
        let start = date(2026, 9, 5), now = date(2026, 9, 19), end = date(2026, 9, 20)
        var deleted = TimeEvent(kind: "a", occurredAt: start); deleted.deletedAt = now
        let data = MarkerOverviewData(events: [deleted, TimeEvent(kind: "a", occurredAt: now), TimeEvent(kind: "a", occurredAt: now.addingTimeInterval(60))], start: start, end: end, granularity: .month, now: now, calendar: cal)
        XCTAssertTrue(data.buckets[0].partial)
        XCTAssertEqual(data.cells.flatMap(\.events).count, 1)
    }
    func testMultiYearAggregationConservesEveryRecord() {
        let start = date(2020, 1, 1), end = date(2026, 9, 20)
        let events = (0..<2200).map { TimeEvent(kind: $0 % 2 == 0 ? "a" : "b", occurredAt: cal.date(byAdding: .day, value: $0, to: start)!) }
        let data = MarkerOverviewData(events: events, start: start, end: end, granularity: .automatic, now: end, calendar: cal)
        XCTAssertEqual(data.granularity, .month)
        XCTAssertEqual(Set(data.cells.flatMap(\.events).map(\.id)), Set(events.map(\.id)))
    }
    func testCalendarBucketsAcrossDaylightSaving() {
        var calendar = cal; calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7))!
        let end = calendar.date(byAdding: .day, value: 3, to: start)!
        let events = (0..<3).map { TimeEvent(kind: "a", occurredAt: calendar.date(byAdding: .day, value: $0, to: start)!) }
        let data = MarkerOverviewData(events: events, start: start, end: end, granularity: .day, now: end, calendar: calendar)
        XCTAssertEqual(data.buckets.count, 3)
        XCTAssertEqual(data.cells.map { $0.events.count }, [1, 1, 1])
    }
    @MainActor func testEditingPreservesIdentityAndSurvivesOlderImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let oldDate = date(2026, 1, 1)
        XCTAssertTrue(store.markEvent(kind: "gym", at: oldDate))
        let old = store.database
        let id = old.events![0].id
        XCTAssertTrue(store.updateEvent(id, kind: "冥想", at: oldDate.addingTimeInterval(60)))
        XCTAssertTrue(store.importRecords(old))
        let reopened = StudyStore(directory: root, observeSystem: false)
        XCTAssertEqual(reopened.database.events?.count, 1)
        XCTAssertEqual(reopened.database.events?.first?.id, id)
        XCTAssertEqual(reopened.database.events?.first?.kind, "冥想")
        XCTAssertEqual(reopened.database.events?.first?.occurredAt, oldDate.addingTimeInterval(60))
        XCTAssertFalse(store.updateEvent(id, kind: " ", at: oldDate))
        XCTAssertTrue(store.setEventDeleted(id, deleted: true))
        XCTAssertFalse(store.updateEvent(id, kind: "gym", at: oldDate))
    }
    func testBubbleAreaProportionalUntilCap() {
        let a = MarkerOverviewData.diameter(count: 1, unit: 5, limit: 40)
        let b = MarkerOverviewData.diameter(count: 4, unit: 5, limit: 40)
        XCTAssertEqual(b * b / (a * a), 4)
        XCTAssertEqual(MarkerOverviewData.diameter(count: 10000, unit: 5, limit: 40), 40)
    }
}
