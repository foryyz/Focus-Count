import XCTest
import FocusCountCore
@testable import FocusCount

final class FocusAnalysisTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    func date(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: day))! }
    func record(_ date: Date, seconds: Double = 1800, name: String = "阅读", deleted: Bool = false) -> StudySession {
        StudySession(startedAt: date, endedAt: date.addingTimeInterval(seconds), activeSeconds: seconds, subject: name, focus: "A", deletedAt: deleted ? date : nil)
    }
    func testWeekStartsMondayAndExcludesFutureDaysFromAverage() {
        let span = FocusAnalysisData.interval(.week, records: [], now: date(11), calendar: calendar)
        XCTAssertEqual(span.start, date(9))
        XCTAssertEqual(span.end, date(12))
        XCTAssertEqual(FocusAnalysisData.dayCount(span, calendar: calendar), 3)
    }
    func testEmptyDatesDSTBoundariesAndDeletedRecords() {
        let span = DateInterval(start: date(7), end: date(10))
        let records = [record(date(7)), record(date(8), deleted: true), record(date(9), seconds: 3600), record(date(10))]
        let buckets = FocusAnalysisData.buckets(records, interval: span, calendar: calendar)
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets.map(\.seconds), [1800, 0, 3600])
        XCTAssertEqual(FocusAnalysisData.dayCount(span, calendar: calendar), 3)
        XCTAssertEqual(FocusAnalysisData.filtered(records, interval: span).count, 2)
    }
    func testCrossMidnightUsesStartDateAndBreakdownConservesTotal() {
        let late = date(7).addingTimeInterval(23 * 3600)
        let values = [record(late, seconds: 7200), record(date(8), seconds: 1200, name: "游戏")]
        let span = DateInterval(start: date(7), end: date(9))
        XCTAssertEqual(FocusAnalysisData.buckets(values, interval: span, calendar: calendar).map(\.seconds), [7200, 1200])
        let groups = FocusAnalysisData.breakdown(values) { $0.subject == "阅读" ? "学习" : "娱乐" }
        XCTAssertEqual(groups.map(\.name), ["学习", "娱乐"])
        XCTAssertEqual(groups.reduce(0) { $0 + $1.seconds }, 8400)
    }
    func testAllRangeAndLongPeriodBucketsHaveNoGaps() {
        let oldest = calendar.date(byAdding: .year, value: -3, to: date(10))!
        let values = [record(oldest), record(date(9)), record(oldest.addingTimeInterval(-86400), deleted: true)]
        let span = FocusAnalysisData.interval(.all, records: values, now: date(10), calendar: calendar)
        XCTAssertEqual(span.start, oldest)
        XCTAssertEqual(FocusAnalysisData.grain(span, calendar: calendar), .month)
        let buckets = FocusAnalysisData.buckets(values, interval: span, calendar: calendar)
        XCTAssertEqual(buckets.first?.start, span.start)
        XCTAssertEqual(buckets.last?.end, span.end)
        for pair in zip(buckets, buckets.dropFirst()) { XCTAssertEqual(pair.0.end, pair.1.start) }
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.records.count }, 2)
    }
    @MainActor func testCategoriesPersistRenameDeleteAndColorsStayStable() {
        let suite = "focus-categories-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let appearance = FocusAppearanceStore(defaults: defaults)
        XCTAssertTrue(appearance.addCategory(" 学习 "))
        XCTAssertFalse(appearance.addCategory("学习"))
        XCTAssertFalse(appearance.addCategory("未分类"))
        XCTAssertFalse(appearance.addCategory(" "))
        let id = appearance.settings.categories[0].id
        appearance.assign("阅读", to: id)
        appearance.ensureColors(["阅读", "游戏"])
        let original = appearance.settings.colors["activity:阅读"]
        appearance.rename(id, to: "自我提升")
        appearance.ensureColors(["阅读", "游戏", "运动"])
        XCTAssertEqual(appearance.settings.colors["activity:阅读"], original)
        let restored = FocusAppearanceStore(defaults: defaults)
        XCTAssertEqual(restored.category("阅读"), "自我提升")
        restored.setColor(.red, key: "activity:阅读")
        XCTAssertNotEqual(FocusAppearanceStore(defaults: defaults).settings.colors["activity:阅读"], original)
        restored.remove(id)
        XCTAssertEqual(restored.category("阅读"), "未分类")
        XCTAssertNil(restored.categoryID("阅读"))
        XCTAssertNotNil(restored.settings.colors["activity:阅读"])
    }
    @MainActor func testUnreadablePreferencesAreNotOverwritten() {
        let suite = "focus-categories-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let invalid = Data("broken".utf8)
        defaults.set(invalid, forKey: "focus-analysis-appearance-v1")
        let appearance = FocusAppearanceStore(defaults: defaults)
        appearance.ensureColors(["阅读"])
        XCTAssertFalse(appearance.addCategory("学习"))
        XCTAssertNotNil(appearance.error)
        XCTAssertEqual(defaults.data(forKey: "focus-analysis-appearance-v1"), invalid)
    }
}
