import FocusCountCore
import XCTest
@testable import FocusCount

final class HistoryTests: XCTestCase {
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
        XCTAssertEqual(store.database.version, 2)
        XCTAssertEqual(store.database.draft.accumulated, 12)
        XCTAssertEqual(store.sessions.first?.updatedAt, Date(timeIntervalSinceReferenceDate: 60))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sessions.v1.backup.json")), original)
        XCTAssertTrue(store.persist())
        XCTAssertEqual(try JSONDecoder().decode(Database.self, from: Data(contentsOf: file)).version, 2)
        let unknown = try JSONEncoder().encode(Database(version: 99))
        try unknown.write(to: file)
        let blocked = StudyStore(directory: root, observeSystem: false)
        XCTAssertTrue(blocked.blocked)
        XCTAssertFalse(blocked.upsert(sample()))
        XCTAssertEqual(try Data(contentsOf: file), unknown)
    }
}
