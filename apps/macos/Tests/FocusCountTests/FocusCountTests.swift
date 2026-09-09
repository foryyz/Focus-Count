import FocusCountCore
import XCTest
@testable import FocusCount
final class FocusCountTests: XCTestCase {
    func testPauseResumeExcludesPause() {
        var timer = TimerState()
        timer.toggle(date: Date(timeIntervalSince1970: 10), now: 100)
        XCTAssertEqual(timer.seconds(now: 110), 10)
        timer.toggle(now: 115)
        XCTAssertEqual(timer.seconds(now: 900), 15)
        timer.toggle(now: 1000)
        timer.pause(now: 1010)
        XCTAssertEqual(timer.seconds(now: 2000), 25)
    }
    func testRecoveryPausedWithElapsedTime() throws {
        var timer = TimerState()
        timer.toggle(now: 100)
        let saved = try JSONEncoder().encode(timer.checkpoint(now: 125))
        let recovered = try JSONDecoder().decode(TimerState.self, from: saved)
        XCTAssertFalse(recovered.isRunning)
        XCTAssertEqual(recovered.seconds(now: 9999), 25)
    }
    func testCSVQuotesUnicodeAndFormulaProtection() {
        let row = StudySession(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60), activeSeconds: 30, subject: "=数学,\"练习\"\n第二章", focus: "S")
        let csv = Storage.csv([row])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("\"'=数学,\"\"练习\"\"\n第二章\""))
        XCTAssertTrue(csv.contains("\"30.000\""))
    }
    func testProjectRootMovesWithApplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent(".focuscount-root"))
        for path in ["dist/macos/FocusCount.app/Contents/MacOS/FocusCount", "apps/macos/.build/debug/FocusCount"] {
            XCTAssertEqual(try Storage.projectDirectory(executable: root.appendingPathComponent(path)).resolvingSymlinksInPath(), root.resolvingSymlinksInPath())
        }
        XCTAssertThrowsError(try Storage.projectDirectory(executable: URL(fileURLWithPath: "/Applications/FocusCount.app/Contents/MacOS/FocusCount")))
    }
    func testLegacyMigrationPreservesOriginalAndDoesNotOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = root.appendingPathComponent("legacy")
        let destination = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = legacy.appendingPathComponent("sessions.json")
        let target = destination.appendingPathComponent("sessions.json")
        var database = Database()
        database.draft.accumulated = 42
        let original = try JSONEncoder().encode(database)
        try original.write(to: source)
        try Storage.migrateLegacyData(from: legacy, to: destination)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: target), original)
        let changed = try JSONEncoder().encode(Database())
        try changed.write(to: source)
        try Storage.migrateLegacyData(from: legacy, to: destination)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }
    func testInvalidLegacyDataDoesNotCreateSharedDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = root.appendingPathComponent("legacy")
        let destination = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for content in [Data("broken".utf8), try JSONEncoder().encode(Database(version: 99))] {
            try content.write(to: legacy.appendingPathComponent("sessions.json"))
            XCTAssertThrowsError(try Storage.migrateLegacyData(from: legacy, to: destination))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("sessions.json").path))
        }
    }
}
