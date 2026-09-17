import XCTest
import FocusCountCore
@testable import FocusCount

final class PhoneStoreTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @MainActor func testCustomMarkersPreserveTimerAndMergeWithMac() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = PhoneStore(directory: root)
        XCTAssertTrue(phone.markCommand(" !Sad "))
        XCTAssertNil(phone.state.clock.startedAt)
        XCTAssertTrue(phone.start(activity: " Reading "))
        let anchor = phone.state.clock.runningSince
        XCTAssertTrue(phone.markCommand("!stop"))
        XCTAssertTrue(phone.markCommand("! 阅读笔记 "))
        XCTAssertFalse(phone.markCommand("!  "))
        XCTAssertFalse(phone.markCommand("sad"))
        XCTAssertEqual(phone.state.events?.map(\.kind), ["sad", "stop", "阅读笔记"])
        XCTAssertEqual(phone.state.clock.runningSince, anchor)
        XCTAssertNil(phone.state.clock.pendingEnd)
        let reopened = PhoneStore(directory: root)
        XCTAssertEqual(reopened.state.activity, "Reading")
        XCTAssertEqual(reopened.state.events?.count, 3)
        let exported = try RecordExchange.decode(phone.export())
        let peer = PhoneStore(directory: root.appendingPathComponent("peer"))
        XCTAssertTrue(peer.importRecords(exported))
        XCTAssertTrue(peer.importRecords(exported))
        XCTAssertEqual(peer.state.events?.count, 3)
        XCTAssertTrue(phone.cancelTimer())
        XCTAssertNil(phone.state.activity)
    }

    @MainActor func testLegacyStateWithoutActivityLoadsAndCompletionClearsActivity() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = try JSONEncoder().encode(PhoneState())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        json.removeValue(forKey: "activity")
        try JSONSerialization.data(withJSONObject: json).write(to: root.appendingPathComponent("app-state.json"))
        let phone = PhoneStore(directory: root)
        XCTAssertFalse(phone.blocked)
        XCTAssertTrue(phone.start(activity: "Writing"))
        XCTAssertFalse(phone.start(activity: "Should not overwrite"))
        phone.finish()
        phone.returnToTimer()
        XCTAssertEqual(phone.state.activity, "Writing")
        XCTAssertTrue(phone.save(sample(), completesTimer: true))
        XCTAssertNil(phone.state.activity)
        XCTAssertNil(phone.state.clock.startedAt)
    }

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

    @MainActor func testSelectedMacFileImportsAndPersists() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let record = sample()
        let file = root.appendingPathComponent("Mac-sessions.json")
        // Mac exports the shared Database, including its own timer draft.
        let mac = Database(sessions: [record], draft: TimerState(startedAt: Date(), accumulated: 123))
        try RecordExchange.encode(mac).write(to: file)
        let selected = try RecordExchange.decode(PhoneImportFile.read(file))
        let store = PhoneStore(directory: root.appendingPathComponent("phone"))
        XCTAssertTrue(store.importRecords(selected))
        XCTAssertEqual(store.sessions.first?.id, record.id)
        XCTAssertNil(store.state.clock.startedAt)
        XCTAssertEqual(PhoneStore(directory: root.appendingPathComponent("phone")).sessions.first?.id, record.id)
        XCTAssertTrue(store.importRecords(selected))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertThrowsError(try PhoneImportFile.read(root.appendingPathComponent("missing.json")))
        try Data("invalid JSON".utf8).write(to: file)
        XCTAssertThrowsError(try RecordExchange.decode(PhoneImportFile.read(file)))
        XCTAssertEqual(store.sessions.count, 1)
    }

    @MainActor func testMacEventsSurvivePhoneExchange() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let event = TimeEvent(kind: "SEX", occurredAt: Date())
        let store = PhoneStore(directory: root)
        XCTAssertTrue(store.importRecords(Database(events: [event])))
        XCTAssertTrue(store.importRecords(Database(events: [event])))
        XCTAssertEqual(try RecordExchange.decode(store.export()).events, [event])
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(PhoneStore(directory: root).state.events, [event])
        XCTAssertTrue(store.importRecords(Database(purgedIDs: [event.id])))
        XCTAssertTrue(store.state.events?.isEmpty == true)
    }

    @MainActor func testEventLifecycleAndCancelTimer() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        XCTAssertTrue(store.save(sample()))
        store.toggle()
        let anchor = store.state.clock.runningSince
        let date = Date(timeIntervalSince1970: 12345)
        XCTAssertTrue(store.markEvent(at: date))
        XCTAssertTrue(store.markEvent(at: date))
        XCTAssertEqual(store.state.events?.count, 2)
        XCTAssertEqual(store.state.clock.runningSince, anchor)
        let id = store.state.events![0].id
        XCTAssertTrue(store.setEventDeleted(id, deleted: true))
        XCTAssertNotNil(store.state.events!.first { $0.id == id }!.deletedAt)
        XCTAssertTrue(store.setEventDeleted(id, deleted: false))
        XCTAssertEqual(store.state.events!.first { $0.id == id }!.occurredAt, date)
        let backup = try RecordExchange.decode(store.export())
        XCTAssertTrue(store.setEventDeleted(id, deleted: true))
        XCTAssertTrue(store.purgeEvents([id]))
        XCTAssertTrue(store.importRecords(backup))
        XCTAssertEqual(store.state.events?.count, 1)
        store.finish()
        XCTAssertTrue(store.cancelTimer())
        XCTAssertNil(store.state.clock.startedAt)
        XCTAssertNil(store.state.clock.pendingEnd)
        XCTAssertEqual(store.sessions.count, 1)
        let reopened = PhoneStore(directory: root)
        XCTAssertEqual(reopened.state.events?.count, 1)
        XCTAssertNil(reopened.state.clock.startedAt)
        store.toggle()
        XCTAssertTrue(store.state.clock.isRunning)
    }
    @MainActor func testEventAndCancelWriteFailureKeepsState() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        store.toggle()
        let anchor = store.state.clock.runningSince
        let file = root.appendingPathComponent("app-state.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertFalse(store.markEvent())
        XCTAssertTrue(store.state.events?.isEmpty ?? true)
        XCTAssertFalse(store.cancelTimer())
        XCTAssertEqual(store.state.clock.runningSince, anchor)
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
        XCTAssertEqual(exported.version, 5)
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
