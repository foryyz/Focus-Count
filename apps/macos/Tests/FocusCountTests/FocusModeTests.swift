import XCTest
import FocusCountCore
@testable import FocusCount

@MainActor final class FocusModeTests: XCTestCase {
    @MainActor func testDeleteAllHistoryPreservesRecordsTimerAndDeletionMarkers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let start = Date().addingTimeInterval(-120)
        let original = StudySession(startedAt: start, endedAt: start.addingTimeInterval(60), activeSeconds: 30, subject: "原活动", focus: "A")
        var edit = original; edit.subject = "新活动"
        let current = RecordExchange.replacing(original, with: edit)
        var deleted = original; deleted.id = UUID()
        var deletedEdit = deleted; deletedEdit.deletedAt = Date()
        deleted = RecordExchange.replacing(deleted, with: deletedEdit)
        let incoming = Database(events: [TimeEvent(kind: "冥想", occurredAt: start)], sessions: [current, deleted])
        XCTAssertTrue(store.importRecords(incoming))
        store.toggle(); store.pause()
        let before = try RecordExchange.decode(store.export())
        XCTAssertEqual(try store.importArchives().count, 2)
        XCTAssertTrue(store.deleteAllHistory())
        XCTAssertTrue(try store.importArchives().isEmpty)
        let after = try RecordExchange.decode(store.export())
        XCTAssertEqual(after.sessions.map(SessionSnapshot.init), before.sessions.map(SessionSnapshot.init))
        XCTAssertEqual(after.events, before.events)
        XCTAssertEqual(after.timerTransfer?.startedAt, before.timerTransfer?.startedAt)
        XCTAssertEqual(after.timerTransfer?.accumulated, before.timerTransfer?.accumulated)
        XCTAssertEqual(RecordExchange.archivedCount(after.sessions), 0)
        XCTAssertTrue(after.sessions.allSatisfy { !($0.purgedHistoryIDs ?? []).isEmpty })
        let reopened = StudyStore(directory: root, observeSystem: false)
        XCTAssertEqual(RecordExchange.archivedCount(try RecordExchange.decode(reopened.export()).sessions), 0)
        XCTAssertTrue(reopened.importRecords(incoming))
        XCTAssertEqual(RecordExchange.archivedCount(try RecordExchange.decode(reopened.export()).sessions), 0)
        XCTAssertTrue(reopened.deleteAllHistory())
        XCTAssertTrue(reopened.deleteAllHistory())
    }
    @MainActor func testDeleteAllHistoryWriteFailureKeepsBackups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        XCTAssertTrue(store.importRecords(Database()))
        let file = root.appendingPathComponent("sessions.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        XCTAssertFalse(store.deleteAllHistory())
        XCTAssertEqual(try store.importArchives().count, 2)
    }

    @MainActor func testDeleteHistoryPersistsWithoutDeletingCurrentRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let start = Date().addingTimeInterval(-120)
        let original = StudySession(startedAt: start, endedAt: start.addingTimeInterval(60), activeSeconds: 30, subject: "原活动", focus: "A")
        var edited = original; edited.subject = "新活动"
        let current = RecordExchange.replacing(original, with: edited)
        let file = Database(sessions: [current])
        XCTAssertTrue(store.importRecords(file))
        XCTAssertTrue(store.deleteVersion(SessionSnapshot(original)))
        XCTAssertFalse(store.restoreVersion(SessionSnapshot(original)))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].subject, "新活动")
        XCTAssertTrue(store.importRecords(file))
        XCTAssertEqual(store.sessions[0].history?.count ?? 0, 0)
        let archive = try XCTUnwrap(store.importArchives().first)
        XCTAssertTrue(store.deleteArchive(archive))
        XCTAssertEqual(try store.importArchives().count, 3)
        let reopened = StudyStore(directory: root, observeSystem: false)
        XCTAssertEqual(reopened.sessions[0].history?.count ?? 0, 0)
        XCTAssertEqual(reopened.sessions[0].subject, "新活动")
    }

    @MainActor func testFailedRecordWriteRollsBackImportedAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let audio = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        let sound = SharedSound(id: UUID().uuidString, name: "原提示音", fileExtension: "aiff", data: try Data(contentsOf: audio), modified: Date())
        var initial = Database(); initial.sounds = [sound]
        XCTAssertTrue(store.importRecords(initial))
        var changed = sound; changed.name = "改名"; changed.modified = Date().addingTimeInterval(1)
        var incoming = Database(events: [TimeEvent(kind: "不应写入", occurredAt: Date())]); incoming.sounds = [changed]
        let file = root.appendingPathComponent("sessions.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        XCTAssertFalse(store.importRecords(incoming))
        let after = try RecordExchange.decode(store.export())
        XCTAssertEqual(after.sounds?.first?.name, "原提示音")
        XCTAssertEqual(after.events?.count ?? 0, 0)
        XCTAssertEqual(try store.importArchives().count, 4)
    }

    @MainActor func testImportOptionsIndependentlyPreserveLocalSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        var local = FocusRoutineSettings(); local.restSound = "Ping"; local.volume = 0.7
        XCTAssertTrue(store.setMode(local))
        var remote = FocusRoutineSettings(); remote.roundMinutes = 45; remote.restSound = "Hero"; remote.volume = 0.2
        var incoming = Database(), shared = SharedSettings()
        shared.entries["mode"] = PreferenceValue(value: try JSONEncoder().encode(ModeParameters(remote)).base64EncodedString(), modified: Date().addingTimeInterval(1))
        incoming.sharedSettings = shared; incoming.soundPreferences = SoundPreferences(remote)
        XCTAssertTrue(store.importRecords(incoming, syncSounds: false, syncParameters: false))
        XCTAssertEqual(store.modeSettings.roundMinutes, 90)
        XCTAssertEqual(store.modeSettings.restSound, "Ping")
        XCTAssertEqual(store.modeSettings.volume, 0.7)
        XCTAssertTrue(store.importRecords(incoming, syncSounds: false))
        XCTAssertEqual(store.modeSettings.roundMinutes, 45)
        XCTAssertEqual(store.modeSettings.restSound, "Ping")
        XCTAssertTrue(store.importRecords(incoming, syncParameters: false))
        XCTAssertEqual(store.modeSettings.restSound, "Hero")
        XCTAssertEqual(store.modeSettings.volume, 0.2)
        let output = try RecordExchange.decode(store.export())
        XCTAssertEqual(output.soundPreferences, SoundPreferences(remote))
        XCTAssertNotNil(output.source)
        XCTAssertEqual(try store.importArchives().count, 6)
    }

    func testSharedSettingsTravelWithOptionalSounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        var incoming = Database(), settings = SharedSettings()
        settings.entries["emoji/sex"] = PreferenceValue(value: "❤️", modified: Date())
        settings.entries["markerColor/sex"] = PreferenceValue(value: "CC5C79", modified: Date())
        incoming.sharedSettings = settings
        incoming.sounds = [SharedSound(id: UUID().uuidString, name: "提醒", fileExtension: "aiff", data: try Data(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")), modified: Date())]
        XCTAssertTrue(store.importRecords(incoming, syncSounds: false))
        let output = try RecordExchange.decode(store.export())
        XCTAssertEqual(output.sharedSettings?.entries["emoji/sex"]?.value, "❤️")
        XCTAssertEqual(output.sounds?.count, 0)
        XCTAssertTrue(store.importRecords(output))
        XCTAssertEqual(try RecordExchange.decode(store.export()).sounds?.count, 0)
        XCTAssertTrue(store.importRecords(incoming))
        XCTAssertEqual(try RecordExchange.decode(store.export()).sounds?.count, 1)
        XCTAssertEqual(try store.importArchives().count, 6)
    }
    func testRestAccountingRestartAndDisable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        var settings = FocusRoutineSettings(); settings.mode = .microBreak
        settings.minimumMinutes = 1; settings.maximumMinutes = 1
        XCTAssertTrue(store.setMode(settings))
        store.toggle()
        store.advanceRoutine(now: StudyClock.now + 65)
        XCTAssertEqual(store.database.focusRoutine?.phase, .microRest)
        XCTAssertEqual(store.database.draft.accumulated, 60, accuracy: 0.05)
        XCTAssertTrue(store.isRunning)
        XCTAssertFalse(store.database.draft.isRunning)
        XCTAssertTrue(store.persist())
        let restored = StudyStore(directory: root, observeSystem: false)
        XCTAssertEqual(restored.database.focusRoutine?.phase, .microRest)
        XCTAssertEqual(restored.database.focusRoutine?.suspended, true)
        XCTAssertFalse(restored.isRunning)
        XCTAssertEqual(restored.database.draft.accumulated, 60, accuracy: 0.05)
        var standard = settings; standard.mode = .standard
        XCTAssertTrue(store.setMode(standard))
        XCTAssertNil(store.database.focusRoutine)
        XCTAssertTrue(store.database.draft.isRunning)
        XCTAssertEqual(store.database.draft.seconds(), 60, accuracy: 0.1)
    }
    func testCancelAndTimerTransferPreservesRoutine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        var settings = FocusRoutineSettings(); settings.mode = .microBreak
        XCTAssertTrue(store.setMode(settings)); store.toggle()
        XCTAssertNotNil(store.database.focusRoutine)
        let snapshot = try RecordExchange.decode(store.export())
        XCTAssertNotNil(snapshot.focusRoutine)
        XCTAssertTrue(store.importRecords(snapshot, syncTimer: true))
        XCTAssertNotNil(store.database.focusRoutine)
        XCTAssertTrue(store.cancelTimer())
        XCTAssertNil(store.database.focusRoutine)
        XCTAssertNil(store.database.draft.startedAt)
    }
}
