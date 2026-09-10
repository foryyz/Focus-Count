import XCTest
@testable import FocusCountCore

final class CoreTests: XCTestCase {
    func sample(_ id: UUID = UUID(), updated: Double = 100) -> StudySession {
        StudySession(id: id, startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60), activeSeconds: 30, subject: "数学", focus: "A", updatedAt: Date(timeIntervalSince1970: updated))
    }
    func testMobileClockSurvivesSuspensionAndRelaunch() throws {
        var clock = MobileClock()
        clock.toggle(at: Date(timeIntervalSince1970: 100))
        let persisted = try JSONEncoder().encode(clock)
        var restored = try JSONDecoder().decode(MobileClock.self, from: persisted)
        XCTAssertTrue(restored.isRunning)
        XCTAssertEqual(restored.seconds(at: Date(timeIntervalSince1970: 3700)), 3600)
        restored.pause(at: Date(timeIntervalSince1970: 3700))
        XCTAssertEqual(restored.seconds(at: Date(timeIntervalSince1970: 9000)), 3600)
        restored.toggle(at: Date(timeIntervalSince1970: 10000))
        restored.finish(at: Date(timeIntervalSince1970: 10010))
        XCTAssertEqual(restored.seconds(), 3610)
        restored.toggle(at: Date(timeIntervalSince1970: 10100))
        XCTAssertFalse(restored.isRunning)
        XCTAssertTrue(restored.isValid)
    }
    func testClockMovingBackwardsNeverAddsNegativeTime() {
        var clock = MobileClock()
        clock.toggle(at: Date(timeIntervalSince1970: 100))
        clock.pause(at: Date(timeIntervalSince1970: 90))
        XCTAssertEqual(clock.accumulated, 0)
    }
    func testMergeNewerRecordsTiesAndDeletionWithoutDuplicates() {
        let local = sample()
        var older = local; older.updatedAt = Date(timeIntervalSince1970: 90); older.subject = "旧科目"
        XCTAssertEqual(RecordExchange.merge(local: [local], incoming: [older]).first?.subject, "数学")
        var tied = local; tied.subject = "相同时间"
        XCTAssertEqual(SessionSnapshot(RecordExchange.merge(local: [local], incoming: [tied])[0]), SessionSnapshot(RecordExchange.merge(local: [tied], incoming: [local])[0]))
        var deleted = local; deleted.updatedAt = Date(timeIntervalSince1970: 200); deleted.deletedAt = deleted.updatedAt
        let merged = RecordExchange.merge(local: [local], incoming: [deleted, sample()])
        XCTAssertEqual(merged.count, 2)
        XCTAssertNotNil(merged.first(where: { $0.id == local.id })?.deletedAt)
        var restored = deleted; restored.deletedAt = nil; restored.updatedAt = Date(timeIntervalSince1970: 300)
        XCTAssertNil(RecordExchange.merge(local: merged, incoming: [restored]).first(where: { $0.id == local.id })?.deletedAt)
    }
    func testImportValidationAndV1Compatibility() throws {
        let session = sample()
        let decoded = try RecordExchange.decode(RecordExchange.encode(Database(version: 1, sessions: [session])))
        XCTAssertEqual(decoded.version, 4)
        XCTAssertEqual(decoded.sessions.first?.id, session.id)
        XCTAssertThrowsError(try RecordExchange.decode(RecordExchange.encode(Database(version: 99))))
        XCTAssertThrowsError(try RecordExchange.decode(RecordExchange.encode(Database(sessions: [session, session]))))
        var invalid = session; invalid.activeSeconds = 120
        XCTAssertThrowsError(try RecordExchange.decode(RecordExchange.encode(Database(sessions: [invalid]))))
        XCTAssertThrowsError(try RecordExchange.decode(Data("not JSON".utf8)))
    }
    func testSharedDateEncodingAndDraftStayCompatibleWithMac() throws {
        var session = sample(); session.startedAt = Date(timeIntervalSinceReferenceDate: 0)
        session.endedAt = Date(timeIntervalSinceReferenceDate: 60)
        let data = try RecordExchange.encode(Database(sessions: [session], draft: TimerState(startedAt: session.startedAt, accumulated: 12)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["startedAt"] as? Double, 0)
        let decoded = try JSONDecoder().decode(Database.self, from: data)
        XCTAssertEqual(decoded.draft.accumulated, 12)
        XCTAssertFalse(decoded.draft.isRunning)
    }
    func testRoundTripsPreserveEveryVersionAndAreIdempotent() throws {
        let original = sample()
        var macEdit = original; macEdit.subject = "物理"; macEdit.updatedAt = Date(timeIntervalSince1970: 200)
        macEdit = RecordExchange.replacing(original, with: macEdit, now: Date(timeIntervalSince1970: 200))
        var phoneEdit = original; phoneEdit.focus = "S"
        phoneEdit = RecordExchange.replacing(original, with: phoneEdit, now: Date(timeIntervalSince1970: 200))
        let forward = RecordExchange.merge(local: [macEdit], incoming: [phoneEdit])
        let reverse = RecordExchange.merge(local: [phoneEdit], incoming: [macEdit])
        XCTAssertEqual(try RecordExchange.encode(Database(sessions: forward)), try RecordExchange.encode(Database(sessions: reverse)))
        let all = Set((forward[0].history ?? []) + [SessionSnapshot(forward[0])])
        XCTAssertEqual(all, Set([SessionSnapshot(original), SessionSnapshot(macEdit), SessionSnapshot(phoneEdit)]))
        var repeated = forward
        for _ in 0..<5 {
            let exported = try RecordExchange.decode(RecordExchange.encode(Database(sessions: repeated)))
            repeated = RecordExchange.merge(local: repeated, incoming: exported.sessions + [phoneEdit, original])
        }
        XCTAssertEqual(try RecordExchange.encode(Database(sessions: repeated)), try RecordExchange.encode(Database(sessions: forward)))
    }
    func testThreeWayMergeIsAssociativeAndRestorationKeepsHistory() throws {
        let a = sample()
        var b = a; b.subject = "英语"; b.updatedAt = Date(timeIntervalSince1970: 200)
        var c = a; c.deletedAt = Date(timeIntervalSince1970: 300); c.updatedAt = c.deletedAt
        let first = RecordExchange.merge(local: RecordExchange.merge(local: [a], incoming: [b]), incoming: [c])
        let second = RecordExchange.merge(local: [a], incoming: RecordExchange.merge(local: [b], incoming: [c]))
        XCTAssertEqual(try RecordExchange.encode(Database(sessions: first)), try RecordExchange.encode(Database(sessions: second)))
        XCTAssertEqual(first[0].history?.count, 2)
        let restored = RecordExchange.replacing(first[0], with: a, now: Date(timeIntervalSince1970: 400))
        XCTAssertNil(restored.deletedAt)
        XCTAssertTrue(restored.history!.contains(SessionSnapshot(c)))
        XCTAssertEqual(RecordExchange.merge(local: [restored], incoming: [c])[0].subject, a.subject)
    }
    func testInvalidHistoryRejectsEntireImport() throws {
        var current = sample()
        current.history = [SessionSnapshot(sample())] // different ID must not enter this history
        XCTAssertThrowsError(try RecordExchange.decode(RecordExchange.encode(Database(sessions: [current]))))
    }
}
