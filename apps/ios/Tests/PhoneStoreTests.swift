import XCTest
import FocusCountCore
@testable import FocusCount

final class PhoneStoreTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @MainActor func testPermanentDeletionSurvivesOldImportsAndRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let record = sample()
        XCTAssertTrue(store.save(record))
        XCTAssertTrue(store.permanentlyDelete([record.id]))
        XCTAssertEqual(store.state.sessions.count, 1)
        store.delete(record)
        XCTAssertTrue(store.permanentlyDelete([record.id]))
        XCTAssertTrue(store.state.sessions.isEmpty)
        XCTAssertTrue(store.importRecords(Database(sessions: [record])))
        XCTAssertTrue(store.state.sessions.isEmpty)
        let reopened = PhoneStore(directory: root)
        XCTAssertTrue(reopened.state.sessions.isEmpty)
        let exported = try RecordExchange.decode(reopened.export())
        XCTAssertTrue(exported.purgedIDs?.contains(record.id) == true)
        let peer = PhoneStore(directory: root.appendingPathComponent("peer"))
        XCTAssertTrue(peer.save(record))
        XCTAssertTrue(peer.importRecords(exported))
        XCTAssertTrue(peer.state.sessions.isEmpty)
        XCTAssertFalse(peer.save(record))
    }
    private func sample() -> StudySession {
        StudySession(startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200), activeSeconds: 60, subject: "数学", focus: "S", updatedAt: Date())
    }
    @MainActor func testEditDeleteRestoreAndRelaunch() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        var session = sample()
        XCTAssertTrue(store.save(session))
        session.subject = "物理"; XCTAssertTrue(store.save(session))
        XCTAssertEqual(store.sessions.count, 1)
        store.delete(session)
        XCTAssertTrue(store.sessions.isEmpty)
        let reopened = PhoneStore(directory: root)
        XCTAssertNotNil(reopened.state.sessions.first?.deletedAt)
        reopened.delete(session, restore: true)
        XCTAssertEqual(reopened.sessions.first?.subject, "物理")
        XCTAssertEqual(reopened.sessions.first?.id, session.id)
    }
    @MainActor func testImportPreservesRunningClockAndMakesBackup() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root); store.toggle()
        let anchor = store.state.clock.runningSince
        XCTAssertTrue(store.importRecords(Database(sessions: [sample()])))
        XCTAssertEqual(store.state.clock.runningSince, anchor)
        XCTAssertTrue(store.state.clock.isRunning)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.lastPathComponent.hasPrefix("before-import-") })
        let exported = try RecordExchange.decode(store.export())
        XCTAssertEqual(exported.sessions.count, 1)
        XCTAssertNotNil(exported.draft.startedAt)
        XCTAssertFalse(exported.draft.isRunning)
    }
    @MainActor func testSaveFailureDoesNotMutateMemory() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        XCTAssertTrue(store.save(sample()))
        let file = root.appendingPathComponent("app-state.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertFalse(store.save(sample()))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNotNil(store.error)
    }
    @MainActor func testCorruptionBlocksWrites() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("app-state.json")
        let corrupt = Data("broken".utf8); try corrupt.write(to: file)
        let store = PhoneStore(directory: root)
        XCTAssertTrue(store.blocked)
        XCTAssertFalse(store.save(sample()))
        XCTAssertThrowsError(try store.export())
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
    @MainActor func testConflictsTravelThroughExportAndCanBeRestored() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let original = sample()
        XCTAssertTrue(store.save(original))
        var changed = original; changed.subject = "Mac 修改"; changed.updatedAt = Date().addingTimeInterval(10)
        XCTAssertTrue(store.importRecords(Database(sessions: [changed])))
        let exported = try RecordExchange.decode(store.export())
        XCTAssertEqual(exported.version, 4)
        XCTAssertEqual(exported.sessions[0].history?.count, 1)
        XCTAssertTrue(store.importRecords(exported))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].history?.count, 1)
        store.restoreVersion(exported.sessions[0].history![0])
        XCTAssertEqual(store.sessions[0].subject, original.subject)
        XCTAssertTrue(store.sessions[0].history!.contains { $0.subject == changed.subject })
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.lastPathComponent.hasPrefix("incoming-") })
    }
}
