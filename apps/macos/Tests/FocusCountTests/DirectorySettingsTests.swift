import XCTest
import FocusCountCore
@testable import FocusCount

final class DirectorySettingsTests: XCTestCase {
    @MainActor func testSelectedImportSampleDoesNotRewritePreviewOrDuplicateRecords() async throws {
        guard let path = ProcessInfo.processInfo.environment["FOCUSCOUNT_IMPORT_SAMPLE"] else {
            throw XCTSkip("Set FOCUSCOUNT_IMPORT_SAMPLE to verify a reported file in an isolated directory.")
        }
        let incoming = try await Task.detached {
            try RecordExchange.decode(ExchangeFileReader.read(URL(fileURLWithPath: path)))
        }.value
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        let before = try Data(contentsOf: root.appendingPathComponent("settings.plist"))
        let started = Date()
        for _ in 0..<50 { _ = store.importPreview(incoming, syncParameters: true) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("settings.plist")), before)
        XCTAssertTrue(store.importRecords(incoming))
        XCTAssertTrue(store.importRecords(incoming))
        XCTAssertEqual(store.database.sessions.count, incoming.sessions.count)
        XCTAssertEqual(store.database.events?.count, incoming.events?.count)
        XCTAssertEqual(store.database.goal, incoming.goal)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "Small-file preview/import must complete promptly")
    }
    @MainActor func testExportChoicesDoNotRestrictImportsOrCompleteBackups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = FilePreferences(directory: root)
        preferences.set(false, forKey: SyncPreferences.goalKey)
        let store = StudyStore(directory: root, observeSystem: false)
        var remote = FocusRoutineSettings(); remote.roundMinutes = 45; remote.standardVolume = 0.8
        var incoming = Database(goal: GoalSnapshot(name: "目标", date: Date()))
        incoming.soundPreferences = SoundPreferences(remote)
        var shared = SharedSettings()
        shared.entries["mode"] = PreferenceValue(value: try JSONEncoder().encode(ModeParameters(remote)).base64EncodedString(), modified: Date())
        shared.entries["focus-target-hidden-v1"] = PreferenceValue(value: "true", modified: Date())
        incoming.sharedSettings = shared
        XCTAssertTrue(store.importRecords(incoming))
        XCTAssertEqual(store.database.goal, incoming.goal)
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
        // Import backups retain excluded fields for recovery.
        let archives = try store.importArchives()
        XCTAssertTrue(try archives.contains { try $0.read().goal == incoming.goal })
    }
    @MainActor func testImportPreviewDoesNotWriteSettingsOrPublishChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        var settings = SharedSettings()
        for index in 0..<12 {
            settings.entries["emoji/event-\(index)"] = PreferenceValue(value: "📚", modified: Date())
        }
        let preferences = FilePreferences(directory: root)
        SharedPreferences.apply(settings, defaults: preferences)
        // Reopen to pick up the imported ledger, as the app does after a restart.
        let reopened = StudyStore(directory: root, observeSystem: false)
        let file = root.appendingPathComponent("settings.plist")
        let before = try Data(contentsOf: file)
        for _ in 0..<20 { _ = reopened.importPreview(Database(), syncParameters: true) }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
    @MainActor func testRestartThenDeleteDirectoryRestoresDefaultModeAndAppearance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        var mode = FocusRoutineSettings(); mode.mode = .microBreak; mode.minimumMinutes = 8; mode.maximumMinutes = 12; mode.roundMinutes = 45; mode.volume = 0.8
        XCTAssertTrue(store.setMode(mode))
        let preferences = FilePreferences(directory: root)
        let colors = MarkerColors(defaults: preferences)
        colors.setEmoji("📚", for: "reading")
        let appearance = FocusAppearanceStore(defaults: preferences)
        XCTAssertTrue(appearance.addCategory("Study"))
        XCTAssertEqual(StudyStore(directory: root, observeSystem: false).modeSettings, mode)
        XCTAssertEqual(MarkerColors(defaults: FilePreferences(directory: root)).emojis["reading"], "📚")
        try FileManager.default.removeItem(at: root)
        let reset = StudyStore(directory: root, observeSystem: false)
        XCTAssertEqual(reset.modeSettings, FocusRoutineSettings())
        XCTAssertTrue(reset.sessions.isEmpty)
        XCTAssertNil(reset.database.goal)
        XCTAssertNil(reset.database.draft.startedAt)
        let empty = FilePreferences(directory: root)
        XCTAssertTrue(MarkerColors(defaults: empty).emojis.isEmpty)
        XCTAssertTrue(FocusAppearanceStore(defaults: empty).settings.categories.isEmpty)
    }
    @MainActor func testCorruptSettingsBlockDatabaseWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("settings.plist"))
        let store = StudyStore(directory: root, observeSystem: false)
        XCTAssertTrue(store.blocked)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.setMode(FocusRoutineSettings()))
    }
}
