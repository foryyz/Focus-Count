import XCTest
import FocusCountCore
@testable import FocusCount

final class PhoneStoreTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @MainActor func testMarkerEditingKeepsIDAndWinsAgainstOldImport() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = PhoneStore(directory: root)
        let time = Date().addingTimeInterval(-3600)
        XCTAssertTrue(phone.markEvent(kind: "gym", at: time))
        let old = try RecordExchange.decode(phone.export())
        let id = phone.state.events![0].id
        XCTAssertTrue(phone.updateEvent(id, kind: "  冥想  ", at: time.addingTimeInterval(60)))
        XCTAssertTrue(phone.importRecords(old))
        let reopened = PhoneStore(directory: root)
        XCTAssertEqual(reopened.state.events?.count, 1)
        XCTAssertEqual(reopened.state.events?.first?.id, id)
        XCTAssertEqual(reopened.state.events?.first?.kind, "冥想")
        XCTAssertEqual(reopened.state.events?.first?.occurredAt, time.addingTimeInterval(60))
        XCTAssertFalse(phone.updateEvent(id, kind: " ", at: time))
        XCTAssertFalse(phone.updateEvent(id, kind: "x", at: Date().addingTimeInterval(86400)))
        XCTAssertTrue(phone.setEventDeleted(id, deleted: true))
        XCTAssertFalse(phone.updateEvent(id, kind: "gym", at: time))
    }
    @MainActor func testMarkerAppearancePersistsAndNewColorsAreDistinct() {
        let suite = "marker-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let colors = MarkerColors(defaults: defaults)
        colors.ensure(["a", "b", "c"])
        XCTAssertEqual(Set(colors.values.values).count, 3)
        let original = colors.values["a"]
        colors.ensure(["a", "d"])
        XCTAssertEqual(colors.values["a"], original)
        colors.setEmoji("🏋️", for: "a")
        XCTAssertEqual(MarkerColors(defaults: defaults).emojis["a"], "🏋️")
        colors.setEmoji("", for: "a")
        XCTAssertNil(MarkerColors(defaults: defaults).emojis["a"])
    }

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

import XCTest
import FocusCountCore
@testable import FocusCount

final class MarkerOverviewTests: XCTestCase {
    private var cal: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func testThirtyDaysRetainEmptyDaysAndSeparateKinds() {
        let start = date(2026, 8, 1), end = date(2026, 8, 31)
        let events = [TimeEvent(kind: "Gym", occurredAt: start), TimeEvent(kind: "gym", occurredAt: start), TimeEvent(kind: "冥想", occurredAt: start)]
        let data = MarkerOverviewData(events: events, start: start, end: end, granularity: .automatic, now: end, calendar: cal)
        XCTAssertEqual(data.granularity, .day)
        XCTAssertEqual(data.buckets.count, 30)
        XCTAssertEqual(data.cells.count, 2)
        XCTAssertEqual(data.cells.first { $0.kind == "gym" }?.events.count, 2)
        XCTAssertEqual(Set(data.cells.flatMap(\.events).map(\.id)), Set(events.map(\.id)))
    }
    func testWeekUsesMondayAndHalfOpenBoundaries() {
        let start = date(2026, 9, 14), boundary = date(2026, 9, 21), end = date(2026, 9, 28)
        let events = [TimeEvent(kind: "a", occurredAt: boundary.addingTimeInterval(-1)), TimeEvent(kind: "a", occurredAt: boundary), TimeEvent(kind: "a", occurredAt: end)]
        let data = MarkerOverviewData(events: events, start: start, end: end, granularity: .week, now: end, calendar: cal)
        XCTAssertEqual(data.buckets.map(\.start), [start, boundary])
        XCTAssertEqual(data.cells.map { $0.events.count }, [1, 1])
        XCTAssertTrue(data.buckets.allSatisfy { !$0.partial })
    }
    func testPartialMonthExcludesDeletedAndFutureRecords() {
        let start = date(2026, 9, 5), now = date(2026, 9, 19), end = date(2026, 9, 20)
        var deleted = TimeEvent(kind: "a", occurredAt: start); deleted.deletedAt = now
        let data = MarkerOverviewData(events: [deleted, TimeEvent(kind: "a", occurredAt: now), TimeEvent(kind: "a", occurredAt: now.addingTimeInterval(60))], start: start, end: end, granularity: .month, now: now, calendar: cal)
        XCTAssertTrue(data.buckets[0].partial)
        XCTAssertEqual(data.cells.flatMap(\.events).count, 1)
    }
    func testMultiYearAggregationConservesEveryRecord() {
        let start = date(2020, 1, 1), end = date(2026, 9, 20)
        let events = (0..<2200).map { TimeEvent(kind: $0 % 2 == 0 ? "a" : "b", occurredAt: cal.date(byAdding: .day, value: $0, to: start)!) }
        let data = MarkerOverviewData(events: events, start: start, end: end, granularity: .automatic, now: end, calendar: cal)
        XCTAssertEqual(data.granularity, .month)
        XCTAssertEqual(Set(data.cells.flatMap(\.events).map(\.id)), Set(events.map(\.id)))
    }
    func testCalendarBucketsAcrossDaylightSaving() {
        var calendar = cal; calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7))!
        let end = calendar.date(byAdding: .day, value: 3, to: start)!
        let events = (0..<3).map { TimeEvent(kind: "a", occurredAt: calendar.date(byAdding: .day, value: $0, to: start)!) }
        let data = MarkerOverviewData(events: events, start: start, end: end, granularity: .day, now: end, calendar: calendar)
        XCTAssertEqual(data.buckets.count, 3)
        XCTAssertEqual(data.cells.map { $0.events.count }, [1, 1, 1])
    }
    func testBubbleAreaProportionalUntilCap() {
        let a = MarkerOverviewData.diameter(count: 1, unit: 5, limit: 40)
        let b = MarkerOverviewData.diameter(count: 4, unit: 5, limit: 40)
        XCTAssertEqual(b * b / (a * a), 4)
        XCTAssertEqual(MarkerOverviewData.diameter(count: 10000, unit: 5, limit: 40), 40)
    }
}

import XCTest
import FocusCountCore
@testable import FocusCount

final class MarkerPointLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var start: Date { Date(timeIntervalSince1970: 0) }
    func testCoincidentRecordsArePlacedSideBySideWithoutChangingTime() {
        let events = (0..<3).map { _ in TimeEvent(kind: "a", occurredAt: start.addingTimeInterval(12 * 3600 + 30 * 60)) }
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 1, width: 200, calendar: calendar)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { !$0.grouped && $0.events.count == 1 })
        XCTAssertEqual(Set(items.map(\.x)).count, 3)
        XCTAssertTrue(items.allSatisfy { $0.y == 375 })
    }
    func testCrowdedRecordsAggregateWithoutLosingAnyEvent() {
        let events = (0..<10).map { _ in TimeEvent(kind: "a", occurredAt: start.addingTimeInterval(3600)) }
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 7, width: 560, calendar: calendar)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].grouped)
        XCTAssertEqual(Set(items.flatMap(\.events).map(\.id)), Set(events.map(\.id)))
        let expanded = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 1, width: 560, calendar: calendar)
        XCTAssertEqual(expanded.count, 10)
    }
    func testTimeSlotsAndVisibleDateFiltering() {
        var deleted = TimeEvent(kind: "a", occurredAt: start); deleted.deletedAt = start
        let events = [TimeEvent(kind: "a", occurredAt: start), TimeEvent(kind: "b", occurredAt: start.addingTimeInterval(23 * 3600 + 59 * 60)), TimeEvent(kind: "c", occurredAt: start.addingTimeInterval(86400)), deleted]
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 1, width: 200, calendar: calendar)
        XCTAssertEqual(items.flatMap(\.events).count, 2)
        XCTAssertEqual(items.map(\.anchorY).min(), 0)
        XCTAssertEqual(items.map(\.anchorY).max()!, 719.5, accuracy: 0.001)
    }
    func testCrowdingGroupsByKindAndSizesByCount() {
        let time = start.addingTimeInterval(12 * 3600)
        let events = (0..<5).map { _ in TimeEvent(kind: "健身", occurredAt: time) } + (0..<2).map { _ in TimeEvent(kind: "冥想", occurredAt: time) }
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 4, width: 560, hourHeight: 12, calendar: calendar)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { Set($0.events.map(\.kind)).count == 1 })
        let large = items.first { $0.events.count == 5 }!
        let small = items.first { $0.events.count == 2 }!
        XCTAssertGreaterThan(large.diameter, small.diameter)
        XCTAssertEqual(Set(items.flatMap(\.events).map(\.id)), Set(events.map(\.id)))
        XCTAssertTrue(abs(large.x - small.x) >= (large.diameter + small.diameter) / 2 || abs(large.y - small.y) >= (large.diameter + small.diameter) / 2)
    }
    func testSeparateRecordsArePreferredWhenTheyFit() {
        let events = (0..<4).map { _ in TimeEvent(kind: "same", occurredAt: start.addingTimeInterval(12 * 3600)) }
        let items = MarkerPointLayout.items(events: events, start: start, offset: 0, visibleDays: 4, width: 560, hourHeight: 12, calendar: calendar)
        XCTAssertEqual(items.count, 4)
        XCTAssertTrue(items.allSatisfy { !$0.grouped })
    }

}
