import FocusCountCore
import XCTest
@testable import FocusCount
final class FocusCountTests: XCTestCase {
    func testCommandSyntax() {
        XCTAssertEqual(FocusCommand(" !stop "), .stop)
        XCTAssertEqual(FocusCommand("!sex"), .sex)
        XCTAssertEqual(FocusCommand(""), .toggle)
        XCTAssertEqual(FocusCommand("stop!"), .unknown)
        XCTAssertEqual(FocusCommand("!sex extra"), .unknown)
    }
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
    @MainActor func testSleepWakeAndCancelPreserveRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let record = StudySession(startedAt: Date().addingTimeInterval(-60), endedAt: Date(), activeSeconds: 30, subject: "已有记录", focus: "A")
        XCTAssertTrue(store.upsert(record))
        store.toggle()
        let anchor = store.database.draft.runningSince
        store.prepareForSleep()
        store.refreshAfterWake()
        XCTAssertEqual(store.database.draft.runningSince, anchor)
        XCTAssertTrue(store.database.draft.isRunning)
        // Simulate an elapsed hour without any UI ticks.
        XCTAssertEqual(store.database.draft.seconds(now: anchor! + 3600), 3600, accuracy: 0.001)
        store.pause()
        store.prepareForSleep()
        store.refreshAfterWake()
        XCTAssertFalse(store.database.draft.isRunning)
        XCTAssertTrue(store.cancelTimer())
        XCTAssertNil(store.database.draft.startedAt)
        XCTAssertEqual(store.database.draft.seconds(), 0)
        XCTAssertEqual(store.sessions.map(\.id), [record.id])
        let reopened = StudyStore(directory: root, observeSystem: false)
        XCTAssertNil(reopened.database.draft.startedAt)
        store.toggle()
        XCTAssertTrue(store.database.draft.isRunning)
        store.finish()
        XCTAssertNotNil(store.database.pendingEnd)
        XCTAssertTrue(store.cancelTimer())
        XCTAssertNil(store.database.pendingEnd)
        XCTAssertEqual(store.sessions.count, 1)
    }

    @MainActor func testCancelFailureKeepsTimer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        store.toggle()
        let anchor = store.database.draft.runningSince
        let file = root.appendingPathComponent("sessions.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertFalse(store.cancelTimer())
        XCTAssertEqual(store.database.draft.runningSince, anchor)
        XCTAssertTrue(store.database.draft.isRunning)
    }


    @MainActor func testTimeMarkersKeepTimerAndRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        store.toggle()
        let anchor = store.database.draft.runningSince
        let time = Date(timeIntervalSince1970: 123456)
        XCTAssertTrue(store.markEvent(at: time))
        XCTAssertTrue(store.markEvent(at: time))
        XCTAssertEqual(store.database.draft.runningSince, anchor)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(store.database.events?.count, 2)
        let data = try store.export()
        let exported = try RecordExchange.decode(data)
        XCTAssertEqual(exported.events?.first?.occurredAt, time)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let eventJSON = (object["events"] as! [[String: Any]])[0]
        XCTAssertNil(eventJSON["activeSeconds"])
        XCTAssertNil(eventJSON["endedAt"])
        XCTAssertTrue(store.importRecords(exported))
        XCTAssertEqual(store.database.events?.count, 2)
        let id = exported.events![0].id
        XCTAssertTrue(store.setEventDeleted(id, deleted: true))
        XCTAssertTrue(store.setEventDeleted(id, deleted: false))
        XCTAssertTrue(store.setEventDeleted(id, deleted: true))
        XCTAssertTrue(store.purgeEvents([id]))
        XCTAssertTrue(store.importRecords(exported))
        XCTAssertEqual(store.database.events?.count, 1)
        XCTAssertEqual(StudyStore(directory: root, observeSystem: false).database.events?.count, 1)
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
        XCTAssertEqual(try RecordExchange.decode(Data(contentsOf: target)).draft.accumulated, 42)
        let changed = try JSONEncoder().encode(Database())
        try changed.write(to: source)
        try Storage.migrateLegacyData(from: legacy, to: destination)
        XCTAssertEqual(try RecordExchange.decode(Data(contentsOf: target)).draft.accumulated, 42)
    }
    func testStandaloneStartupAndMigrationMerge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Application Support/FocusCount")
        XCTAssertNoThrow(try Storage.migrateProjectData(executable: root.appendingPathComponent("Applications/FocusCount.app/Contents/MacOS/FocusCount"), to: destination))
        let project = root.appendingPathComponent("checkout")
        let source = project.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data().write(to: project.appendingPathComponent(".focuscount-root"))
        let record = StudySession(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60), activeSeconds: 30, subject: "项目数据", focus: "A")
        let other = StudySession(startedAt: record.startedAt, endedAt: record.endedAt, activeSeconds: 30, subject: "已有本地数据", focus: "S")
        let original = try RecordExchange.encode(Database(sessions: [record]))
        try original.write(to: source.appendingPathComponent("sessions.json"))
        try RecordExchange.encode(Database(sessions: [other])).write(to: destination.appendingPathComponent("sessions.json"))
        try Storage.migrateProjectData(executable: project.appendingPathComponent("dist/macos/FocusCount.app/Contents/MacOS/FocusCount"), to: destination)
        let merged = try RecordExchange.decode(Data(contentsOf: destination.appendingPathComponent("sessions.json")))
        XCTAssertEqual(Set(merged.sessions.map(\.id)), [record.id, other.id])
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("sessions.json")), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("project-storage-migration.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("backups").path).count, 1)
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
