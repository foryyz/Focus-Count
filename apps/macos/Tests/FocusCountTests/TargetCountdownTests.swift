import XCTest
import FocusCountCore
@testable import FocusCount

final class TargetCountdownTests: XCTestCase {
    @MainActor func testImportedGoalIsHiddenAndLocalPrivacyNeverExports() {
        let suite = "GoalPrivacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let incoming = GoalSnapshot(name: "私密目标", date: Date())
        let store = TargetCountdownStore(defaults: defaults, snapshot: incoming, writer: { _ in true })
        XCTAssertEqual(store.target?.hidden, true)
        var target = store.target!; target.hidden = false
        XCTAssertTrue(store.save(target))
        store.hide()
        store.receive(GoalSnapshot(name: "更新目标", date: Date()))
        XCTAssertEqual(store.target?.hidden, true)
        let failed = TargetCountdownStore(defaults: defaults, snapshot: incoming, writer: { _ in false })
        target.name = "无法保存的新目标"
        XCTAssertFalse(failed.save(target))
        XCTAssertFalse(failed.remove())
        XCTAssertEqual(failed.target?.name, incoming.name)
    }
    @MainActor func testMacGoalRoundTripPersistsAndOldFileCannotRestoreDeletedGoal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let goal = GoalSnapshot(name: "考试", date: Date())
        XCTAssertTrue(store.updateGoal(goal))
        XCTAssertEqual(try RecordExchange.decode(store.export()).goal, goal)
        var deleted = goal; deleted.deleted = true; deleted.updatedAt = goal.updatedAt.addingTimeInterval(1)
        XCTAssertTrue(store.importRecords(Database(goal: deleted)))
        XCTAssertTrue(store.importRecords(Database(goal: goal)))
        XCTAssertEqual(StudyStore(directory: root, observeSystem: false).database.goal, deleted)
    }
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
