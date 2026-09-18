import XCTest
import FocusCountCore
@testable import FocusCount

final class EventAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return result
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    func testFrequencyUsesIntervalsAndNormalizesLegacyCase() {
        let events = [TimeEvent(kind: "SEX", occurredAt: date(1)), TimeEvent(kind: "sex", occurredAt: date(8)), TimeEvent(kind: " sex ", occurredAt: date(15)), TimeEvent(kind: "sad", occurredAt: date(2))]
        let result = EventAnalytics.frequencies(events)
        XCTAssertEqual(result.first?.id, "sex")
        XCTAssertEqual(result.first?.count, 3)
        XCTAssertEqual(result.first?.weeksPerOccurrence, 1)
        XCTAssertNil(result.last?.weeksPerOccurrence)
        XCTAssertEqual(EventAnalytics.intervalText(nil), "暂无间隔")
    }
    func testDateRangeIncludesLocalWholeDaysAndExcludesDeleted() {
        var deleted = TimeEvent(kind: "sex", occurredAt: date(18))
        deleted.deletedAt = date(18)
        let events = [TimeEvent(kind: "sad", occurredAt: date(17, hour: 0)), TimeEvent(kind: "sad", occurredAt: date(18, hour: 23)), TimeEvent(kind: "sad", occurredAt: date(16, hour: 23)), TimeEvent(kind: "sad", occurredAt: date(19, hour: 0)), deleted]
        let filtered = EventAnalytics.records(events, days: 2, now: date(18), calendar: calendar)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(EventAnalytics.records(events, days: nil, now: date(18), calendar: calendar).count, 4)
        XCTAssertEqual(filtered.first?.occurredAt, date(18, hour: 23))
        XCTAssertEqual(EventAnalytics.frequencies(events).first?.count, 4)
    }
    func testBucketsUseLocalDayAndKeepEveryOccurrence() {
        let events = [TimeEvent(kind: "a", occurredAt: date(1, hour: 23)), TimeEvent(kind: "a", occurredAt: date(2, hour: 0)), TimeEvent(kind: "a", occurredAt: date(2, hour: 0))]
        let buckets = EventAnalytics.buckets(events, component: .day, calendar: calendar)
        XCTAssertEqual(buckets.map(\.count), [1, 2])
        XCTAssertEqual(buckets.last?.id, date(2, hour: 0))
        let sameTime = EventAnalytics.frequencies(Array(events.suffix(2)))
        XCTAssertEqual(sameTime.first?.weeksPerOccurrence, 0)
        XCTAssertEqual(EventAnalytics.buckets([], component: .day).count, 0)
    }
}
