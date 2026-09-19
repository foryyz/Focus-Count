import XCTest
import SwiftUI
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
    func testWeekAlwaysStartsMondayAndHandlesSunday() {
        XCTAssertEqual(EventAnalytics.periodStart(range: -1, now: date(20), calendar: calendar), date(14, hour: 0))
        XCTAssertEqual(EventAnalytics.periodStart(range: -1, now: date(21), calendar: calendar), date(21, hour: 0))
        XCTAssertNil(EventAnalytics.periodStart(range: 0, now: date(20), calendar: calendar))
    }
    func testHourDistributionUsesLocalTimeAndExcludesTrash() {
        var deleted = TimeEvent(kind: "a", occurredAt: date(1, hour: 23)); deleted.deletedAt = date(2)
        let counts = EventAnalytics.hours([TimeEvent(kind: "a", occurredAt: date(1, hour: 0)), TimeEvent(kind: "a", occurredAt: date(2, hour: 23)), deleted], calendar: calendar)
        XCTAssertEqual(counts.count, 24)
        XCTAssertEqual(counts[0], 1); XCTAssertEqual(counts[23], 1)
        XCTAssertEqual(counts.reduce(0, +), 2)
    }
    @MainActor func testColorsPersistAndNewLabelsDoNotRecolorExistingOnes() {
        let suite = "FocusCount-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let colors = MarkerColors(defaults: defaults)
        colors.ensure(["sex", "健身"])
        let original = colors.values
        colors.ensure(["冥想", "sex", "健身"])
        XCTAssertEqual(colors.values["sex"], original["sex"])
        XCTAssertEqual(Set(colors.values.values).count, 3)
        colors.set(.red, for: "sex")
        let reopened = MarkerColors(defaults: defaults)
        XCTAssertEqual(reopened.values["sex"], colors.values["sex"])
        XCTAssertNotEqual(reopened.values["sex"], original["sex"])
        reopened.ensure(["sex", "新标记"])
        XCTAssertEqual(reopened.values["sex"], colors.values["sex"])
        var used: Set<String> = []
        for _ in 0..<40 { let next = MarkerColors.nextColor(used: used); XCTAssertFalse(used.contains(next)); used.insert(next) }
    }

}
