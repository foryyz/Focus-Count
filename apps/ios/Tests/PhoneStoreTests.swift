import XCTest
import SwiftUI
import UIKit
import FocusCountCore
@testable import FocusCount

final class PhoneStoreTests: XCTestCase {
    @MainActor func testHomeNavigationPausesAndResumesExistingTimer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        for mode in FocusMode.allCases {
            var settings = FocusRoutineSettings(); settings.mode = mode
            XCTAssertTrue(store.setMode(settings)); XCTAssertTrue(store.start(activity: "课程"))
            let id = store.state.timerID
            let activity = store.state.activity
            let phase = store.state.routine?.phase
            let remaining = store.state.routine?.remaining
            store.returnHome()
            XCTAssertTrue(store.showingHome)
            XCTAssertFalse(store.isRunning)
            XCTAssertEqual(store.state.timerID, id)
            XCTAssertEqual(store.state.activity, activity)
            XCTAssertEqual(store.state.routine?.phase, phase)
            XCTAssertEqual(store.state.routine?.remaining ?? 0, remaining ?? 0, accuracy: 0.5)
            XCTAssertTrue(store.resumeFocus())
            XCTAssertFalse(store.showingHome)
            XCTAssertTrue(store.isRunning)
            XCTAssertEqual(store.state.timerID, id)
            store.toggle()
            let pausedState = try JSONEncoder().encode(store.state)
            store.returnHome()
            XCTAssertFalse(store.isRunning)
            let afterNavigation = try JSONEncoder().encode(store.state)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: pausedState) as? NSDictionary,
                           try JSONSerialization.jsonObject(with: afterNavigation) as? NSDictionary)
            XCTAssertTrue(store.resumeFocus())
            XCTAssertFalse(store.showingHome)
            XCTAssertTrue(store.isRunning)
            XCTAssertEqual(store.state.timerID, id)
            store.returnHome()
            XCTAssertTrue(store.cancelTimer())
            XCTAssertFalse(store.showingHome)
            XCTAssertFalse(store.resumeFocus())
        }
    }
    @MainActor func testExportChoicesDoNotRestrictImportsOrCompleteBackups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let preferences = UserDefaults(suiteName: "FocusCount-test-" + Data(root.path.utf8).base64EncodedString())!
        preferences.set(false, forKey: SyncPreferences.goalKey)
        var remote = FocusRoutineSettings(); remote.roundMinutes = 45; remote.standardVolume = 0.8
        var incoming = Database(goal: GoalSnapshot(name: "目标", date: Date()))
        incoming.soundPreferences = SoundPreferences(remote)
        var shared = SharedSettings()
        shared.entries["mode"] = PreferenceValue(value: try JSONEncoder().encode(ModeParameters(remote)).base64EncodedString(), modified: Date())
        shared.entries["focus-target-hidden-v1"] = PreferenceValue(value: "true", modified: Date())
        incoming.sharedSettings = shared
        XCTAssertTrue(store.importRecords(incoming))
        XCTAssertEqual(store.state.goal, incoming.goal)
        XCTAssertEqual(store.modeSettings.roundMinutes, 45)
        XCTAssertEqual(store.modeSettings.standardVolume, 0.8)
        let filtered = try RecordExchange.decode(store.export())
        XCTAssertNil(filtered.goal); XCTAssertNil(filtered.soundPreferences); XCTAssertNil(filtered.sounds)
        XCTAssertNil(filtered.sharedSettings?.entries["mode"])
        XCTAssertNil(filtered.sharedSettings?.entries["focus-target-hidden-v1"])
        let complete = try RecordExchange.decode(store.export(forBackup: true))
        XCTAssertEqual(complete.goal, incoming.goal)
        XCTAssertNotNil(complete.soundPreferences)
        XCTAssertNotNil(complete.sharedSettings?.entries["mode"])
        preferences.set(true, forKey: SyncPreferences.goalKey)
        preferences.set(true, forKey: SyncPreferences.soundsKey)
        preferences.set(true, forKey: SyncPreferences.parametersKey)
        let included = try RecordExchange.decode(store.export())
        XCTAssertEqual(included.goal, incoming.goal)
        XCTAssertNotNil(included.soundPreferences)
        XCTAssertNotNil(included.sharedSettings?.entries["mode"])
    }
    @MainActor func testIndependentModeVolumesPersistAndUpdateActiveCourse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        var settings = FocusRoutineSettings(); settings.mode = .course
        settings.standardVolume = 0.2; settings.microBreakVolume = 0.6; settings.courseVolume = 0.9
        XCTAssertTrue(store.setMode(settings)); XCTAssertTrue(store.start(activity: "课程"))
        XCTAssertEqual(store.state.routine?.settings.volume, 0.9)
        settings.courseVolume = 0.3
        XCTAssertTrue(store.setMode(settings))
        XCTAssertEqual(store.state.routine?.settings.volume, 0.3)
        let reopened = PhoneStore(directory: root)
        XCTAssertFalse(reopened.blocked)
        XCTAssertEqual(reopened.modeSettings.standardVolume, 0.2)
        XCTAssertEqual(reopened.modeSettings.microBreakVolume, 0.6)
        XCTAssertEqual(reopened.modeSettings.courseVolume, 0.3)
        let exported = try RecordExchange.decode(store.export(forBackup: true))
        XCTAssertEqual(exported.soundPreferences?.standardVolume, 0.2)
        XCTAssertEqual(exported.soundPreferences?.microBreakVolume, 0.6)
        XCTAssertEqual(exported.soundPreferences?.courseVolume, 0.3)
    }
    @MainActor func testCoursePlanCyclesAndSchedulesClassBells() throws {
        var settings = FocusRoutineSettings(); settings.mode = .course
        settings.lessonMinutes = 1; settings.classBreakMinutes = 1
        let date = Date()
        var plan = PhoneRoutine(settings: settings, at: date)
        XCTAssertEqual(plan.advance(at: date.addingTimeInterval(70)), 60)
        XCTAssertEqual(plan.phase, .longRest)
        XCTAssertEqual(plan.remaining, 50)
        XCTAssertEqual(plan.advance(at: date.addingTimeInterval(120 * 100 + 30)), 5970)
        XCTAssertEqual(plan.phase, .focus)
        XCTAssertEqual(plan.remaining, 30)
        XCTAssertTrue(plan.isValid)
        XCTAssertTrue(plan.portable.isValid)
        let reminders = plan.reminders(at: plan.anchor)
        XCTAssertEqual(reminders.count, 64)
        XCTAssertEqual(reminders[0].phase, .longRest)
        XCTAssertEqual(reminders[1].phase, .focus)
        XCTAssertEqual(reminders[0].date.timeIntervalSince(plan.anchor), 30)
        plan.suspended = true
        XCTAssertTrue(plan.reminders(at: plan.anchor).isEmpty)
        XCTAssertEqual(plan.advance(at: plan.anchor.addingTimeInterval(90)), 0)
        let restored = try JSONDecoder().decode(PhoneRoutine.self, from: JSONEncoder().encode(plan))
        XCTAssertTrue(restored.isValid)
        XCTAssertEqual(restored.remaining, 30)
    }
    @MainActor func testCourseStoreSurvivesRestRestartAndTimerTransfer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let peerRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: peerRoot) }
        let store = PhoneStore(directory: root)
        var settings = FocusRoutineSettings(); settings.mode = .course
        settings.lessonMinutes = 1; settings.classBreakMinutes = 1
        settings.startSound = "Ping"; settings.pauseSound = "Hero"
        XCTAssertTrue(store.setMode(settings))
        var incoming = Database()
        let start = Date().addingTimeInterval(-70)
        incoming.timerTransfer = TimerTransfer(capturedAt: start, startedAt: start, accumulated: 0, isRunning: true, pendingEnd: nil, activity: "课程", timerID: UUID())
        incoming.focusRoutine = FocusRoutine(settings: settings)
        XCTAssertTrue(store.importRecords(incoming, syncTimer: true, syncSounds: false, syncParameters: false))
        XCTAssertEqual(store.state.routine?.phase, .longRest)
        XCTAssertEqual(store.state.clock.accumulated, 60, accuracy: 0.1)
        let remainingRest = store.state.routine?.remaining ?? 0
        store.returnHome()
        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.state.routine?.phase, .longRest)
        XCTAssertTrue(store.resumeFocus())
        XCTAssertTrue(store.isRunning)
        XCTAssertEqual(store.state.routine?.phase, .longRest)
        XCTAssertEqual(store.state.routine?.remaining ?? 0, remainingRest, accuracy: 0.5)
        store.toggle()
        XCTAssertFalse(store.isRunning)
        let reopened = PhoneStore(directory: root)
        XCTAssertFalse(reopened.blocked)
        XCTAssertEqual(reopened.state.routine?.phase, .longRest)
        let peer = PhoneStore(directory: peerRoot)
        XCTAssertTrue(peer.importRecords(try RecordExchange.decode(store.export(forBackup: true)), syncTimer: true))
        XCTAssertEqual(peer.state.routine?.settings.mode, .course)
        XCTAssertEqual(peer.modeSettings.startSound, "Ping")
        peer.toggle(); peer.skipRest()
        XCTAssertTrue(peer.isRunning)
        XCTAssertEqual(peer.state.routine?.phase, .focus)
        XCTAssertEqual(peer.state.routine?.settings.mode, .course)
        XCTAssertTrue(peer.cancelTimer())
        XCTAssertNil(peer.state.routine)
    }
    @MainActor func testDeleteAllHistoryPreservesRecordsTimerAndDeletionMarkers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let start = Date().addingTimeInterval(-120)
        let original = StudySession(startedAt: start, endedAt: start.addingTimeInterval(60), activeSeconds: 30, subject: "原活动", focus: "A")
        var edit = original; edit.subject = "新活动"
        let current = RecordExchange.replacing(original, with: edit)
        var deleted = original; deleted.id = UUID()
        var deletedEdit = deleted; deletedEdit.deletedAt = Date()
        deleted = RecordExchange.replacing(deleted, with: deletedEdit)
        let incoming = Database(events: [TimeEvent(kind: "冥想", occurredAt: start)], sessions: [current, deleted])
        XCTAssertTrue(store.importRecords(incoming))
        XCTAssertTrue(store.start(activity: "正在计时")); store.toggle()
        let before = try RecordExchange.decode(store.export(forBackup: true))
        XCTAssertEqual(try store.importArchives().count, 2)
        XCTAssertTrue(store.deleteAllHistory())
        XCTAssertTrue(try store.importArchives().isEmpty)
        let after = try RecordExchange.decode(store.export(forBackup: true))
        XCTAssertEqual(after.sessions.map(SessionSnapshot.init), before.sessions.map(SessionSnapshot.init))
        XCTAssertEqual(after.events, before.events)
        XCTAssertEqual(after.timerTransfer?.startedAt, before.timerTransfer?.startedAt)
        XCTAssertEqual(after.timerTransfer?.accumulated, before.timerTransfer?.accumulated)
        XCTAssertEqual(RecordExchange.archivedCount(after.sessions), 0)
        XCTAssertTrue(after.sessions.allSatisfy { !($0.purgedHistoryIDs ?? []).isEmpty })
        let reopened = PhoneStore(directory: root)
        XCTAssertEqual(RecordExchange.archivedCount(try RecordExchange.decode(reopened.export(forBackup: true)).sessions), 0)
        XCTAssertTrue(reopened.importRecords(incoming))
        XCTAssertEqual(RecordExchange.archivedCount(try RecordExchange.decode(reopened.export(forBackup: true)).sessions), 0)
        XCTAssertTrue(reopened.deleteAllHistory())
        XCTAssertTrue(reopened.deleteAllHistory())
    }
    @MainActor func testDeleteAllHistoryWriteFailureKeepsBackups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        XCTAssertTrue(store.importRecords(Database()))
        let file = root.appendingPathComponent("app-state.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        XCTAssertFalse(store.deleteAllHistory())
        XCTAssertEqual(try store.importArchives().count, 2)
    }

    @MainActor func testDeleteHistoryPersistsWithoutDeletingCurrentRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let start = Date().addingTimeInterval(-120)
        let original = StudySession(startedAt: start, endedAt: start.addingTimeInterval(60), activeSeconds: 30, subject: "原活动", focus: "A")
        var edited = original; edited.subject = "新活动"
        let current = RecordExchange.replacing(original, with: edited)
        let file = Database(sessions: [current])
        XCTAssertTrue(store.importRecords(file))
        XCTAssertTrue(store.deleteVersion(SessionSnapshot(original)))
        store.restoreVersion(SessionSnapshot(original))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].subject, "新活动")
        XCTAssertTrue(store.importRecords(file))
        XCTAssertEqual(store.sessions[0].history?.count ?? 0, 0)
        let archive = try XCTUnwrap(store.importArchives().first)
        XCTAssertTrue(store.deleteArchive(archive))
        XCTAssertEqual(try store.importArchives().count, 3)
        let reopened = PhoneStore(directory: root)
        XCTAssertEqual(reopened.sessions[0].history?.count ?? 0, 0)
        XCTAssertEqual(reopened.sessions[0].subject, "新活动")
    }

    @MainActor func testFailedRecordWriteRollsBackImportedAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let audio = try XCTUnwrap(PhoneSounds(directory: root).url("Glass"))
        let sound = SharedSound(id: UUID().uuidString, name: "原提示音", fileExtension: "wav", data: try Data(contentsOf: audio), modified: Date())
        var initial = Database(); initial.sounds = [sound]
        XCTAssertTrue(store.importRecords(initial))
        var changed = sound; changed.name = "改名"; changed.modified = Date().addingTimeInterval(1)
        var incoming = Database(events: [TimeEvent(kind: "不应写入", occurredAt: Date())]); incoming.sounds = [changed]
        let file = root.appendingPathComponent("app-state.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        XCTAssertFalse(store.importRecords(incoming))
        let after = try RecordExchange.decode(store.export(forBackup: true))
        XCTAssertEqual(after.sounds?.first?.name, "原提示音")
        XCTAssertEqual(after.events?.count ?? 0, 0)
        XCTAssertEqual(try store.importArchives().count, 4)
    }

    @MainActor func testImportOptionsIndependentlyPreserveLocalSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
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
        let output = try RecordExchange.decode(store.export(forBackup: true))
        XCTAssertEqual(output.soundPreferences, SoundPreferences(remote))
        XCTAssertNotNil(output.source)
        XCTAssertEqual(try store.importArchives().count, 6)
    }

    @MainActor func testModePauseRestartAndTimerImport() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        var settings = FocusRoutineSettings(); settings.mode = .microBreak
        XCTAssertTrue(store.setMode(settings))
        XCTAssertTrue(store.start(activity: "阅读"))
        XCTAssertNotNil(store.state.routine)
        store.toggle()
        XCTAssertTrue(store.state.routine!.suspended)
        XCTAssertFalse(store.isRunning)
        let restored = PhoneStore(directory: root)
        XCTAssertTrue(restored.state.routine!.suspended)
        XCTAssertEqual(restored.modeSettings.mode, .microBreak)
        restored.toggle()
        XCTAssertTrue(restored.isRunning)
        restored.finish()
        XCTAssertTrue(restored.state.routine!.suspended)
        XCTAssertTrue(restored.state.routine!.reminders(at: Date()).isEmpty)
        restored.returnToTimer()
        XCTAssertTrue(restored.cancelTimer())
        XCTAssertNil(restored.state.routine)
        let normal = PhoneStore(directory: root.appendingPathComponent("peer"))
        XCTAssertTrue(normal.start(activity: "普通计时"))
        XCTAssertTrue(restored.start(activity: "阅读"))
        XCTAssertTrue(restored.importRecords(try RecordExchange.decode(normal.export(forBackup: true)), syncTimer: true))
        XCTAssertNil(restored.state.routine)
        XCTAssertTrue(restored.isRunning)
    }
    func testBackgroundPlanAndRemindersUseSameTimeline() throws {
        var settings = FocusRoutineSettings(); settings.mode = .microBreak
        settings.minimumMinutes = 1; settings.maximumMinutes = 1
        settings.microSeconds = 10; settings.roundMinutes = 3; settings.restMinutes = 1
        let start = Date(timeIntervalSince1970: 1000)
        var plan = PhoneRoutine(settings: settings, at: start)
        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.reminders(at: start).map { $0.date.timeIntervalSince(start) }, [60, 70, 130, 140, 180, 240])
        XCTAssertEqual(plan.advance(at: start.addingTimeInterval(65)), 60)
        XCTAssertEqual(plan.phase, .microRest)
        XCTAssertEqual(plan.remaining, 5)
        var restored = try JSONDecoder().decode(PhoneRoutine.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.advance(at: start.addingTimeInterval(500)), 100)
        XCTAssertEqual(restored.phase, .ready)
        XCTAssertTrue(restored.reminders(at: start.addingTimeInterval(500)).isEmpty)
        plan.suspended = true
        XCTAssertEqual(plan.advance(at: start.addingTimeInterval(90)), 0)
        XCTAssertEqual(plan.remaining, 5)
        XCTAssertTrue(plan.reminders(at: start.addingTimeInterval(90)).isEmpty)
        plan.skipRest(at: start.addingTimeInterval(90))
        XCTAssertEqual(plan.phase, .focus)
        XCTAssertTrue(plan.suspended)
        XCTAssertTrue(PhoneRoutine.supports(FocusRoutineSettings()))
        settings.roundMinutes = 360
        XCTAssertFalse(PhoneRoutine.supports(settings))
    }
    @MainActor func testPhoneSoundImportAndNotificationConversion() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sounds = PhoneSounds(directory: root)
        let preset = try XCTUnwrap(sounds.url("Glass"))
        try sounds.add(preset)
        let entry = try XCTUnwrap(sounds.custom.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(sounds.url(entry.id)).path))
        sounds.rename(entry.id, name: "我的轻铃")
        XCTAssertEqual(PhoneSounds(directory: root).custom.first?.name, "我的轻铃")
        XCTAssertNoThrow(try sounds.notificationSound(entry.id))
        let invalid = root.appendingPathComponent("invalid.wav")
        try Data("invalid".utf8).write(to: invalid)
        XCTAssertThrowsError(try sounds.add(invalid))
    }
    @MainActor func testSoundDeletionClearsFilesCacheAndModeReferences() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("sounds"), sounds = PhoneSounds(directory: root.appendingPathComponent("sounds"))
        try sounds.add(XCTUnwrap(sounds.url("Glass")))
        let sound = try XCTUnwrap(sounds.custom.first), source = try XCTUnwrap(sounds.url(sounds.custom[0].id))
        XCTAssertNotNil(sounds.notice)
        XCTAssertFalse(sounds.rename(sound.id, name: "  "))
        XCTAssertTrue(sounds.rename(sound.id, name: "新名称"))
        XCTAssertNil(sounds.error)
        _ = try sounds.notificationSound(sound.id)
        let cache = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds/" + sound.id + ".caf")
        let store = PhoneStore(directory: root)
        var mode = FocusRoutineSettings(); mode.mode = .microBreak; mode.restSound = sound.id; mode.focusSound = sound.id
        XCTAssertTrue(store.setMode(mode)); XCTAssertTrue(store.start(activity: "Test"))
        XCTAssertTrue(store.deleteCustomSound(sound.id))
        XCTAssertNil(store.modeSettings.restSound)
        XCTAssertNil(store.state.routine?.settings.focusSound)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(PhoneSounds(directory: folder).custom.isEmpty)
        XCTAssertNil(PhoneStore(directory: root).modeSettings.focusSound)
        XCTAssertFalse(store.deleteCustomSound("Glass"))
    }
    @MainActor func testNumericSettingsAndRestStateExchangeWithOptionalSounds() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        var incoming = Database()
        var shared = SharedSettings()
        shared.entries["emoji/冥想"] = PreferenceValue(value: "🧘", modified: Date())
        shared.entries["markerColor/冥想"] = PreferenceValue(value: "AABBCC", modified: Date())
        incoming.sharedSettings = shared
        var settings = FocusRoutineSettings(); settings.mode = .microBreak
        var routine = FocusRoutine(settings: settings)
        routine.phase = .microRest; routine.remaining = 8; routine.roundRemaining = 400; routine.suspended = true
        incoming.focusRoutine = routine
        incoming.timerTransfer = TimerTransfer(capturedAt: Date(), startedAt: Date().addingTimeInterval(-120), accumulated: 100, isRunning: false, pendingEnd: nil, activity: "阅读", timerID: UUID())
        let asset = try XCTUnwrap(PhoneSounds(directory: root).url("Glass"))
        incoming.sounds = [SharedSound(id: UUID().uuidString, name: "我的铃声", fileExtension: "wav", data: try Data(contentsOf: asset), modified: Date())]
        XCTAssertTrue(store.importRecords(incoming, syncTimer: true, syncSounds: false))
        XCTAssertEqual(store.state.routine?.phase, .microRest)
        XCTAssertEqual(store.state.routine?.remaining, 8)
        XCTAssertEqual(store.state.clock.seconds(), 100)
        let output = try RecordExchange.decode(store.export(forBackup: true))
        XCTAssertEqual(output.sharedSettings?.entries["emoji/冥想"]?.value, "🧘")
        XCTAssertEqual(output.sharedSettings?.entries["markerColor/冥想"]?.value, "AABBCC")
        XCTAssertEqual(output.sounds?.count, 0)
        XCTAssertNil(output.focusRoutine?.settings.restSound)
        XCTAssertEqual(output.focusRoutine?.phase, .microRest)
        let peer = PhoneStore(directory: root.appendingPathComponent("peer"))
        XCTAssertTrue(peer.importRecords(output, syncTimer: true))
        XCTAssertEqual(peer.state.routine?.phase, .microRest)
        XCTAssertTrue(store.importRecords(incoming))
        XCTAssertEqual(try RecordExchange.decode(store.export(forBackup: true)).sounds?.count, 1)
        XCTAssertEqual(try store.importArchives().count, 4)

    }
    @MainActor func testGoalExchangeAndDeletionSurviveRestart() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = PhoneStore(directory: root)
        let goal = GoalSnapshot(name: "目标", date: Date())
        XCTAssertTrue(phone.importRecords(Database(goal: goal)))
        XCTAssertEqual(try RecordExchange.decode(phone.export(forBackup: true)).goal, goal)
        var deleted = goal; deleted.deleted = true; deleted.updatedAt = goal.updatedAt.addingTimeInterval(1)
        XCTAssertTrue(phone.updateGoal(deleted))
        XCTAssertTrue(phone.importRecords(Database(goal: goal)))
        XCTAssertEqual(PhoneStore(directory: root).state.goal, deleted)
    }
    @MainActor func testCompletedHandoffCannotBeResurrected() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = PhoneStore(directory: root)
        XCTAssertTrue(phone.start(activity: "阅读"))
        let file = try RecordExchange.decode(phone.export(forBackup: true))
        let peer = PhoneStore(directory: root.appendingPathComponent("peer"))
        XCTAssertTrue(peer.importRecords(file, syncTimer: true))
        XCTAssertEqual(peer.state.timerID, phone.state.timerID)
        peer.finish()
        let record = StudySession(startedAt: peer.state.clock.startedAt!, endedAt: peer.state.clock.pendingEnd!,
            activeSeconds: peer.state.clock.seconds(), subject: "阅读", focus: "A")
        XCTAssertTrue(peer.save(record, completesTimer: true))
        XCTAssertEqual(peer.sessions.first?.id, file.timerTransfer?.timerID)
        XCTAssertFalse(peer.importRecords(file, syncTimer: true))
        XCTAssertNil(peer.state.clock.startedAt)
        phone.finish()
        let other = StudySession(startedAt: phone.state.clock.startedAt!, endedAt: phone.state.clock.pendingEnd!,
            activeSeconds: phone.state.clock.seconds(), subject: "阅读", focus: "A")
        XCTAssertTrue(phone.save(other, completesTimer: true))
        XCTAssertTrue(peer.importRecords(try RecordExchange.decode(phone.export(forBackup: true))))
        XCTAssertEqual(peer.sessions.count, 1)
    }
    @MainActor func testTimerHandoffIsExplicitAndPersists() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = PhoneStore(directory: root)
        XCTAssertTrue(phone.start(activity: "本机活动"))
        let original = phone.state.clock.startedAt
        let now = Date()
        let transfer = TimerTransfer(capturedAt: now.addingTimeInterval(-20), startedAt: now.addingTimeInterval(-120),
            accumulated: 60, isRunning: true, pendingEnd: nil, activity: "阅读")
        let incoming = Database(timerTransfer: transfer)
        XCTAssertTrue(phone.importRecords(incoming))
        XCTAssertEqual(phone.state.clock.startedAt, original)
        XCTAssertTrue(phone.importRecords(incoming, syncTimer: true))
        XCTAssertTrue(phone.state.clock.isRunning)
        XCTAssertEqual(phone.state.clock.seconds(), 80, accuracy: 2)
        XCTAssertEqual(phone.state.activity, "阅读")
        XCTAssertTrue(phone.importRecords(incoming, syncTimer: true))
        XCTAssertEqual(phone.state.clock.seconds(), 80, accuracy: 2)
        let reopened = PhoneStore(directory: root)
        XCTAssertTrue(reopened.state.clock.isRunning)
        let outgoing = try RecordExchange.decode(phone.export(forBackup: true)).timerTransfer!
        XCTAssertEqual(outgoing.timerState().seconds(), phone.state.clock.seconds(), accuracy: 0.1)
        XCTAssertEqual(outgoing.activity, "阅读")
        XCTAssertFalse(phone.importRecords(Database(), syncTimer: true))
        XCTAssertTrue(phone.state.clock.isRunning)
        var paused = transfer; paused.isRunning = false; paused.pendingEnd = now.addingTimeInterval(-30)
        XCTAssertTrue(phone.importRecords(Database(timerTransfer: paused), syncTimer: true))
        XCTAssertEqual(phone.state.clock.pendingEnd, paused.pendingEnd)
        XCTAssertEqual(phone.state.clock.seconds(), 60, accuracy: 0.01)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("before-import-") })
    }

    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @MainActor func testMarkerEditingKeepsIDAndWinsAgainstOldImport() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let phone = PhoneStore(directory: root)
        let time = Date().addingTimeInterval(-3600)
        XCTAssertTrue(phone.markEvent(kind: "gym", at: time))
        let old = try RecordExchange.decode(phone.export(forBackup: true))
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
        let exported = try RecordExchange.decode(phone.export(forBackup: true))
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
        let exported = try RecordExchange.decode(reopened.export(forBackup: true))
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
        XCTAssertEqual(try RecordExchange.decode(store.export(forBackup: true)).events, [event])
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
        let backup = try RecordExchange.decode(store.export(forBackup: true))
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
        let exported = try RecordExchange.decode(store.export(forBackup: true))
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
        XCTAssertThrowsError(try store.export(forBackup: true))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
    @MainActor func testConflictsTravelThroughExportAndCanBeRestored() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let original = sample()
        XCTAssertTrue(store.save(original))
        var changed = original; changed.subject = "Mac 修改"; changed.updatedAt = Date().addingTimeInterval(10)
        XCTAssertTrue(store.importRecords(Database(sessions: [changed])))
        let exported = try RecordExchange.decode(store.export(forBackup: true))
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

// Render synthetic records at a compact phone size for visual regression review.
// The store is isolated; no personal records are read or changed.
@MainActor final class PhoneLayoutTests: XCTestCase {
    func testCompactAndLandscapeScreens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -29, to: today)!
        let end = cal.date(byAdding: .day, value: 1, to: today)!
        let names = ["阅读", "健身", "冥想", "散步", "写作", "咖啡"]
        let events = (0..<180).map { index in
            TimeEvent(kind: names[index % names.count], occurredAt: start.addingTimeInterval(Double(index % 29) * 86400 + Double(6 + index % 17) * 3600))
        }
        let sessions = (0..<30).map { index in
            let date = cal.date(byAdding: .day, value: -(index % 20), to: today)!
            return StudySession(startedAt: date, endedAt: date.addingTimeInterval(3600), activeSeconds: Double((index % 5 + 1) * 600), subject: names[index % names.count], focus: "A")
        }
        XCTAssertTrue(store.importRecords(Database(events: events, sessions: sessions)))
        let suite = "PhoneLayout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let colors = MarkerColors(defaults: defaults)
        colors.ensure(names)
        for (name, emoji) in zip(names, ["📚", "🏋️", "🧘", "🚶", "✍️", "☕️"]) { colors.setEmoji(emoji, for: name) }
        let appearance = FocusAppearanceStore(defaults: defaults)
        appearance.ensureColors(names)
        let goal = GoalSnapshot(name: "准备一场很重要的考试", emoji: "🎓", date: Date().addingTimeInterval(90000))
        var goalWrites = 0
        let countdown = TargetCountdownStore(defaults: defaults, snapshot: goal, writer: { _ in goalWrites += 1; return true })
        countdown.setHidden(false)
        countdown.setTotalHours(true)
        XCTAssertEqual(countdown.target?.hidden, false)
        XCTAssertEqual(TargetCountdownStore(defaults: defaults, snapshot: goal).totalHours, true)
        await render(PhoneCountdownFooter(store: countdown, edit: {}).padding(.horizontal, 80).ignoresSafeArea(), name: "countdown-footer-compact", size: CGSize(width: 375, height: 100))
        await render(PhoneTargetSettings(store: countdown), name: "countdown-settings-visible", size: CGSize(width: 375, height: 667))
        countdown.setHidden(true)
        await render(PhoneTargetSettings(store: countdown), name: "countdown-settings-hidden", size: CGSize(width: 375, height: 667))
        XCTAssertEqual(goalWrites, 0)
        await render(TimerScreen(store: store), name: "home-compact", size: CGSize(width: 375, height: 667))
        await render(PhoneTodaySheet(store: store, appearance: appearance), name: "today-compact", size: CGSize(width: 375, height: 667))
        await render(PhoneFocusAnalysis(store: store, appearance: appearance), name: "analysis-compact", size: CGSize(width: 375, height: 667))
        await render(PhoneMarkerCharts(mode: .constant(0), events: events, start: start, end: end, isWeek: false, colors: colors, edit: { _ in }, delete: { _ in }, compact: true).padding(), name: "frequency-compact", size: CGSize(width: 375, height: 460))
        var dense: [TimeEvent] = []
        for name in names.prefix(3) {
            for (day, count) in [1, 2, 3, 4, 5, 10, 100].enumerated() {
                let date = cal.date(byAdding: .day, value: day, to: start)!
                dense += (0..<count).map { _ in TimeEvent(kind: name, occurredAt: date) }
            }
        }
        await render(MarkerFrequencyOverview(events: dense, start: start, end: cal.date(byAdding: .day, value: 7, to: start)!, isWeek: true, colors: colors, edit: { _ in }, delete: { _ in }, compact: true).padding(), name: "frequency-counts-small", size: CGSize(width: 375, height: 460))

        await render(PhoneMarkerCharts(mode: .constant(2), events: events, start: start, end: end, isWeek: false, colors: colors, edit: { _ in }, delete: { _ in }, compact: true).padding(), name: "time-compact", size: CGSize(width: 375, height: 460))
        await render(PhoneMarkerCharts(mode: .constant(2), events: events, start: start, end: end, isWeek: false, colors: colors, edit: { _ in }, delete: { _ in }, compact: true).padding(), name: "time-landscape", size: CGSize(width: 740, height: 310))
    }
    func testModeScreens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        var settings = FocusRoutineSettings(); settings.mode = .microBreak
        XCTAssertTrue(store.setMode(settings))
        await render(TimerScreen(store: store), name: "mode-home-small", size: CGSize(width: 375, height: 667))
        await render(PhoneModeMenu(store: store, adjust: {}), name: "mode-menu", size: CGSize(width: 375, height: 410))
        await render(PhoneModeSettings(store: store), name: "mode-settings-small", size: CGSize(width: 375, height: 667))
        await render(PhoneModeSettings(store: store), name: "mode-settings-landscape", size: CGSize(width: 740, height: 350))
        settings.mode = .course
        XCTAssertTrue(store.setMode(settings))
        await render(PhoneModeSettings(store: store), name: "course-settings-small", size: CGSize(width: 375, height: 667))
        await render(PhoneModeSettings(store: store), name: "course-settings-landscape", size: CGSize(width: 740, height: 350))
        settings.mode = .standard
        XCTAssertTrue(store.setMode(settings))
        await render(PhoneModeSettings(store: store), name: "standard-sounds-small", size: CGSize(width: 375, height: 667))
        try store.soundLibrary.add(XCTUnwrap(store.soundLibrary.url("Glass")))
        if let sound = store.soundLibrary.custom.first { store.soundLibrary.rename(sound.id, name: "我的自定义提示音") }
        await render(PhoneSoundSettings(store: store), name: "sound-library", size: CGSize(width: 375, height: 667))
    }
    func testMilestoneThemeScreens() async throws {
        let suite = "ThemeLayout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        let start = Calendar.current.startOfDay(for: Date())
        XCTAssertTrue(store.importRecords(Database(sessions: [StudySession(startedAt: start,
            endedAt: start.addingTimeInterval(3600), activeSeconds: 3600, subject: "阅读", focus: "A")])))
        defaults.set(true, forKey: FocusMilestone.themeKey)
        await render(TimerScreen(store: store).defaultAppStorage(defaults), name: "theme-rewards-home", size: CGSize(width: 375, height: 667))
        defaults.set(false, forKey: FocusMilestone.themeKey)
        await render(TimerScreen(store: store).defaultAppStorage(defaults), name: "theme-classic-home", size: CGSize(width: 375, height: 667))
        for hours in 0...10 {
            await render(MilestoneHero(seconds: Double(hours * 3600 + 42 * 60), fontSize: 64)
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white)
                .environment(\.colorScheme, .light), name: "milestone-\(hours)h", size: CGSize(width: 375, height: 280))
        }
        await render(MilestoneHero(seconds: 36000, fontSize: 64)
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            .environment(\.colorScheme, .dark),
            name: "milestone-achieved-dark", size: CGSize(width: 375, height: 280))
    }
    func testEffectPreviewAndHorizontalMilestones() async throws {
        for hours in 0...10 {
            await render(ThemeEffectPreview(hours: Double(hours)), name: "effect-preview-\(hours)h", size: CGSize(width: 375, height: 667))
        }
        for hours in [0, 7, 8, 9, 10] {
            await render(MilestoneHero(seconds: Double(hours * 3600 + 42 * 60), fontSize: 92, horizontal: true)
                .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white)
                .environment(\.colorScheme, .light), name: "horizontal-milestone-\(hours)h", size: CGSize(width: 920, height: 300))
        }
    }
    func testReturnHomeScreens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        XCTAssertTrue(store.start(activity: "阅读"))
        await render(TimerScreen(store: store), name: "focus-back-button", size: CGSize(width: 375, height: 667))
        store.returnHome()
        await render(TimerScreen(store: store), name: "resume-home-small", size: CGSize(width: 375, height: 667))
        await render(TimerScreen(store: store), name: "resume-home-landscape", size: CGSize(width: 740, height: 350))
        XCTAssertFalse(store.isRunning)
        XCTAssertTrue(store.resumeFocus())
        XCTAssertTrue(store.isRunning)
    }
    func testExchangeScreens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhoneStore(directory: root)
        var incoming = Database(events: [TimeEvent(kind: "冥想", occurredAt: Date())])
        incoming.source = ExchangeSource(device: "工作 Mac", platform: "macOS")
        incoming.soundPreferences = SoundPreferences(FocusRoutineSettings())
        var settings = SharedSettings()
        settings.entries["mode"] = PreferenceValue(value: try JSONEncoder().encode(ModeParameters(FocusRoutineSettings())).base64EncodedString(), modified: Date())
        incoming.sharedSettings = settings
        incoming.timerTransfer = TimerTransfer(capturedAt: Date(), startedAt: Date().addingTimeInterval(-30), accumulated: 10, isRunning: false, pendingEnd: nil, activity: "阅读", timerID: UUID())
        await render(ExchangeScreen(store: store, initialImport: incoming), name: "exchange-preview-small", size: CGSize(width: 375, height: 667))
        XCTAssertTrue(store.importRecords(incoming))
        await render(PhoneVersionHistory(store: store), name: "exchange-history-small", size: CGSize(width: 375, height: 667))
    }
    private func render<V: View>(_ view: V, name: String, size: CGSize) async {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(image.size, size)
        window.isHidden = true
    }
}
