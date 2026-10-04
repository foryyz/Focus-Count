import XCTest
@testable import FocusCountCore

final class FocusMilestoneTests: XCTestCase {
    func testHourBoundaries() {
        let boundaries: [(Double, FocusMilestone)] = [(0, .beginning), (1, .blue), (2, .ice), (3, .violet), (4, .silver),
            (5, .jewel), (6, .roseGold), (7, .gold), (8, .radiant), (9, .finalPush), (10, .achieved)]
        for (index, boundary) in boundaries.enumerated() {
            XCTAssertEqual(FocusMilestone(seconds: boundary.0 * 3600), boundary.1)
            if index > 0 {
                XCTAssertEqual(FocusMilestone(seconds: boundary.0 * 3600 - 1), boundaries[index - 1].1)
            }
        }
        XCTAssertEqual(FocusMilestone.allCases.count, 11)
        XCTAssertFalse(FocusMilestone(seconds: 21599).lightsHome)
        XCTAssertTrue(FocusMilestone(seconds: 21600).lightsHome)
        XCTAssertEqual(FocusMilestone(seconds: 20 * 3600), .achieved)
        XCTAssertEqual(FocusMilestone(seconds: -.infinity), .beginning)
        XCTAssertEqual(FocusMilestone(seconds: .nan), .beginning)
    }
    func testRemainingAchievementMinutesRoundsUpAtTheFinalMinute() {
        XCTAssertNil(FocusMilestone.remainingAchievementMinutes(seconds: 32399))
        XCTAssertEqual(FocusMilestone.remainingAchievementMinutes(seconds: 32400), 60)
        XCTAssertEqual(FocusMilestone.remainingAchievementMinutes(seconds: 34920), 18)
        XCTAssertEqual(FocusMilestone.remainingAchievementMinutes(seconds: 35940), 1)
        XCTAssertEqual(FocusMilestone.remainingAchievementMinutes(seconds: 35999.9), 1)
        XCTAssertNil(FocusMilestone.remainingAchievementMinutes(seconds: 36000))
        XCTAssertNil(FocusMilestone.remainingAchievementMinutes(seconds: .nan))
        XCTAssertNil(FocusMilestone.remainingAchievementMinutes(seconds: .infinity))
        XCTAssertTrue(FocusMilestone.finalPush.encouragement.isEmpty)
    }
    func testPreviewAndManualCelebrationsDoNotConsumeDailyClaim() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FilePreferences(directory: root)
        let date = Date(timeIntervalSince1970: 1791000000)
        for reason in [FocusCelebration.Reason.preview, .manual] {
            XCTAssertFalse(FocusCelebration.request(seconds: 35999, reason: reason, at: date, storage: storage))
            XCTAssertTrue(FocusCelebration.request(seconds: 36000, reason: reason, at: date, storage: storage))
            XCTAssertTrue(FocusCelebration.request(seconds: 36000, reason: reason, at: date, storage: storage))
        }
        XCTAssertTrue(FocusCelebration.request(seconds: 36000, reason: .automatic, at: date, storage: storage))
        XCTAssertFalse(FocusCelebration.request(seconds: 36000, reason: .automatic, at: date, storage: storage))
        XCTAssertTrue(FocusCelebration.request(seconds: 36000, reason: .manual, at: date, storage: storage))
        XCTAssertTrue(FocusMilestone.achieved.encouragement.isEmpty)
    }
    func testCelebrationOncePerLocalDayAndPersistedTheme() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FilePreferences(directory: root)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 23, minute: 59))!
        XCTAssertFalse(storage.bool(forKey: FocusMilestone.themeKey))
        storage.set(true, forKey: FocusMilestone.themeKey)
        XCTAssertFalse(FocusCelebration.claim(seconds: 35999, at: date, calendar: calendar, storage: storage))
        XCTAssertTrue(FocusCelebration.claim(seconds: 36000, at: date, calendar: calendar, storage: storage))
        XCTAssertFalse(FocusCelebration.claim(seconds: 40000, at: date, calendar: calendar, storage: storage))
        let reopened = FilePreferences(directory: root)
        XCTAssertTrue(reopened.bool(forKey: FocusMilestone.themeKey))
        reopened.set(false, forKey: FocusMilestone.themeKey)
        reopened.set(true, forKey: FocusMilestone.themeKey)
        XCTAssertFalse(FocusCelebration.claim(seconds: 36000, at: date, calendar: calendar, storage: reopened))
        XCTAssertTrue(FocusCelebration.claim(seconds: 36000, at: date.addingTimeInterval(120), calendar: calendar, storage: reopened))
    }
}
