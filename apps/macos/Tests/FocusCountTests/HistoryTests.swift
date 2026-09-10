import FocusCountCore
import XCTest
@testable import FocusCount

final class HistoryTests: XCTestCase {

    @MainActor func testPermanentDeletionSurvivesOldImportsAndRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root)
        let record = sample()
        XCTAssertTrue(store.upsert(record))
        XCTAssertTrue(store.permanentlyDelete([record.id]))
        XCTAssertEqual(store.database.sessions.count, 1)
        store.setDeleted(record.id, deleted: true)
        XCTAssertTrue(store.permanentlyDelete([record.id]))
        XCTAssertTrue(store.database.sessions.isEmpty)
        XCTAssertTrue(store.importRecords(Database(sessions: [record])))
        XCTAssertTrue(store.database.sessions.isEmpty)
        let reopened = StudyStore(directory: root)
        XCTAssertTrue(reopened.database.sessions.isEmpty)
        let exported = try RecordExchange.decode(reopened.export())
        XCTAssertTrue(exported.purgedIDs?.contains(record.id) == true)
        let peer = StudyStore(directory: root.appendingPathComponent("peer"))
        XCTAssertTrue(peer.upsert(record))
        XCTAssertTrue(peer.importRecords(exported))
        XCTAssertTrue(peer.database.sessions.isEmpty)
        XCTAssertFalse(peer.upsert(record))
    }
    private func sample() -> StudySession {
        StudySession(startedAt: Date(timeIntervalSince1970: 1000), endedAt: Date(timeIntervalSince1970: 4600), activeSeconds: 1800, subject: "数学", focus: "A")
    }
    func testValidationKeepsActiveTimeIndependentOfInterval() {
        var session = sample()
        XCTAssertNil(session.validationError)
        session.endedAt = session.startedAt.addingTimeInterval(60)
        XCTAssertNotNil(session.validationError)
        session.activeSeconds = 30
        XCTAssertNil(session.validationError)
        session.activeSeconds = .nan
        XCTAssertNotNil(session.validationError)
        session.activeSeconds = 30
        session.subject = " \n"
        XCTAssertNotNil(session.validationError)
    }
    func testDateSubjectFocusAndTrashFilters() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = sample()
        var next = sample()
        next.startedAt = Date(timeIntervalSince1970: 86400)
        next.subject = "英语"
        next.focus = "S"
        var deleted = first
        deleted.id = UUID()
        deleted.deletedAt = Date()
        let all = [first, next, deleted]
        var filter = HistoryFilter(start: first.startedAt, end: first.startedAt, allDates: false)
        XCTAssertEqual(filter.apply(all, calendar: calendar).map(\.id), [first.id])
        filter.allDates = true
        filter.subject = "英语"
        filter.focus = "S"
        XCTAssertEqual(filter.apply(all, calendar: calendar).map(\.id), [next.id])
        filter = HistoryFilter(deleted: true)
        XCTAssertEqual(filter.apply(all, calendar: calendar).map(\.id), [deleted.id])
    }
    @MainActor func testEditDeleteRestorePersistAndLeaveDraftUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        store.database.draft.accumulated = 12
        var session = sample()
        XCTAssertTrue(store.upsert(session))
        session.subject = "  物理  "
        XCTAssertTrue(store.upsert(session))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.subject, "物理")
        XCTAssertNotNil(store.sessions.first?.updatedAt)
        XCTAssertEqual(store.database.draft.accumulated, 12)
        XCTAssertTrue(store.setDeleted(session.id, deleted: true))
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(Storage.csv(store.database.sessions).contains(session.id.uuidString))
        let restoredStore = StudyStore(directory: root, observeSystem: false)
        XCTAssertNotNil(restoredStore.database.sessions.first?.deletedAt)
        XCTAssertTrue(restoredStore.setDeleted(session.id, deleted: false))
        XCTAssertEqual(restoredStore.sessions.first?.id, session.id)
        XCTAssertTrue(Storage.csv(restoredStore.database.sessions).contains(session.id.uuidString))
    }
    @MainActor func testSaveFailureRollsBackMemory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let session = sample()
        XCTAssertTrue(store.upsert(session))
        let original = try Data(contentsOf: root.appendingPathComponent("sessions.json"))
        // A directory at the destination cannot be replaced with an atomic JSON file.
        try FileManager.default.removeItem(at: root.appendingPathComponent("sessions.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions.json"), withIntermediateDirectories: false)
        XCTAssertFalse(store.setDeleted(session.id, deleted: true))
        XCTAssertEqual(store.sessions.first?.id, session.id)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(original.isEmpty)
    }
    @MainActor func testV1UpgradeBacksUpAndUnknownVersionBlocksWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("{\"version\":1,\"sessions\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"startedAt\":0,\"endedAt\":60,\"activeSeconds\":30,\"subject\":\"数学\",\"focus\":\"S\"}],\"draft\":{\"accumulated\":12}}".utf8)
        let file = root.appendingPathComponent("sessions.json")
        try original.write(to: file)
        let store = StudyStore(directory: root, observeSystem: false)
        XCTAssertFalse(store.blocked)
        XCTAssertEqual(store.database.version, 4)
        XCTAssertEqual(store.database.draft.accumulated, 12)
        XCTAssertEqual(store.sessions.first?.updatedAt, Date(timeIntervalSinceReferenceDate: 60))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sessions.v1.backup.json")), original)
        XCTAssertTrue(store.persist())
        XCTAssertEqual(try JSONDecoder().decode(Database.self, from: Data(contentsOf: file)).version, 4)
        let unknown = try JSONEncoder().encode(Database(version: 99))
        try unknown.write(to: file)
        let blocked = StudyStore(directory: root, observeSystem: false)
        XCTAssertTrue(blocked.blocked)
        XCTAssertFalse(blocked.upsert(sample()))
        XCTAssertEqual(try Data(contentsOf: file), unknown)
    }
    @MainActor func testImportBacksUpBothSidesPreservesDraftAndVersions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let original = sample()
        XCTAssertTrue(store.upsert(original))
        store.database.draft.toggle(now: 100)
        let running = store.database.draft.runningSince
        var incoming = original; incoming.subject = "另一端修改"; incoming.updatedAt = Date().addingTimeInterval(10)
        XCTAssertTrue(store.importRecords(Database(sessions: [incoming])))
        XCTAssertEqual(store.database.draft.runningSince, running)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].subject, incoming.subject)
        XCTAssertEqual(store.sessions[0].history?.count, 1)
        let backupFolders = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(backupFolders.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFolders[0].appendingPathComponent("before-import.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFolders[0].appendingPathComponent("incoming.json").path))
        let exported = try RecordExchange.decode(store.export())
        XCTAssertEqual(exported.sessions[0].history?.count, 1)
        XCTAssertTrue(store.restoreVersion(exported.sessions[0].history![0]))
        XCTAssertEqual(store.sessions[0].subject, original.subject)
        XCTAssertTrue(store.sessions[0].history!.contains { $0.subject == incoming.subject })
    }
    @MainActor func testImportFailureAndInvalidFileDoNotChangeRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        XCTAssertTrue(store.upsert(sample()))
        XCTAssertFalse(store.importRecords(Database(version: 99)))
        XCTAssertEqual(store.sessions.count, 1)
        // Block backup creation: nothing may be merged if backup cannot be written.
        try Data().write(to: root.appendingPathComponent("backups"))
        XCTAssertFalse(store.importRecords(Database(sessions: [sample()])))
        XCTAssertEqual(store.sessions.count, 1)
    }
    @MainActor func testV2MigrationKeepsModificationTimestamps() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var record = sample(); record.updatedAt = Date(timeIntervalSince1970: 9000)
        try RecordExchange.encode(Database(version: 2, sessions: [record])).write(to: root.appendingPathComponent("sessions.json"))
        let store = StudyStore(directory: root, observeSystem: false)
        XCTAssertFalse(store.blocked)
        XCTAssertEqual(store.sessions[0].updatedAt, record.updatedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions.v2.backup.json").path))
    }
}
