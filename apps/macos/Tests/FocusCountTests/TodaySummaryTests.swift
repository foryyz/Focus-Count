import XCTest
import FocusCountCore
@testable import FocusCount

final class TodaySummaryTests: XCTestCase {
    func testLocalDayBoundariesDeletedRecordsAndDraft() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        XCTAssertEqual(end.timeIntervalSince(start), 23 * 3600)
        let sessions = [
            StudySession(startedAt: start, endedAt: start.addingTimeInterval(3600), activeSeconds: 1800, subject: "阅读", focus: "A"),
            StudySession(startedAt: start.addingTimeInterval(-600), endedAt: start.addingTimeInterval(600), activeSeconds: 1200, subject: "跨午夜", focus: "A"),
            StudySession(startedAt: end, endedAt: end.addingTimeInterval(60), activeSeconds: 60, subject: "明天", focus: "A"),
            StudySession(startedAt: start, endedAt: start.addingTimeInterval(60), activeSeconds: 60, subject: "已删", focus: "A", deletedAt: start)
        ]
        let events = [TimeEvent(kind: "早", occurredAt: start), TimeEvent(kind: "晚", occurredAt: end.addingTimeInterval(-1)),
                      TimeEvent(kind: "昨天", occurredAt: start.addingTimeInterval(-1)), TimeEvent(kind: "明天", occurredAt: end),
                      TimeEvent(kind: "已删", occurredAt: start, deletedAt: start)]
        let database = Database(events: events, sessions: sessions, draft: TimerState(startedAt: start, accumulated: 500))
        let summary = TodaySummary(database: database, now: start.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(summary.seconds, 1800)
        XCTAssertEqual(summary.sessions.count, 1)
        XCTAssertEqual(summary.events.map(\.kind), ["晚", "早"])
        let nextDay = TodaySummary(database: database, now: end, calendar: calendar)
        XCTAssertEqual(nextDay.seconds, 60)
        XCTAssertEqual(nextDay.events.map(\.kind), ["明天"])
    }
    func testEmptyDay() {
        let summary = TodaySummary(database: Database())
        XCTAssertEqual(summary.seconds, 0)
        XCTAssertTrue(summary.sessions.isEmpty)
        XCTAssertTrue(summary.events.isEmpty)
    }
}
