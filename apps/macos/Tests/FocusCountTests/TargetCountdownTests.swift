import XCTest
@testable import FocusCount

final class TargetCountdownTests: XCTestCase {
    func testCountdownBoundariesAndDateOnlyMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let target = TargetDate(name: "目标", emoji: "", date: day.addingTimeInterval(36000), includesTime: false, hidden: false)
        XCTAssertEqual(target.deadline(calendar: calendar), day)
        XCTAssertEqual(target.remaining(now: day.addingTimeInterval(-90000), calendar: calendar), "还有 1 天 1 小时")
        XCTAssertEqual(target.remaining(now: day.addingTimeInterval(-59), calendar: calendar), "不足 1 小时")
        XCTAssertEqual(target.remaining(now: day, calendar: calendar), "目标日到了")
        XCTAssertEqual(target.remaining(now: day.addingTimeInterval(86400), calendar: calendar), "已过去 1 天")
        var timed = target
        timed.includesTime = true
        XCTAssertEqual(timed.remaining(now: day, calendar: calendar), "还有 0 天 10 小时")
    }

    @MainActor func testHiddenTargetSurvivesReloadAndDelete() {
        let suite = "TargetCountdownTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TargetCountdownStore(defaults: defaults)
        let target = TargetDate(name: "私密目标", emoji: "🎓", date: Date(), includesTime: true, hidden: false)
        store.save(target)
        XCTAssertEqual(TargetCountdownStore(defaults: defaults).target, target)
        store.hide()
        let reloaded = TargetCountdownStore(defaults: defaults)
        XCTAssertEqual(reloaded.target?.hidden, true)
        XCTAssertEqual(reloaded.target?.name, target.name)
        reloaded.remove()
        XCTAssertNil(TargetCountdownStore(defaults: defaults).target)
    }
}
