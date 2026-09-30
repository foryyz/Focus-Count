import XCTest
@testable import FocusCountCore

final class ExchangePreviewTests: XCTestCase {
    func testDeletingArchiveAlsoRemovesHiddenLegacyCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try RecordExchange.encode(Database())
        for name in ["before-import-complete-test.json", "before-import-test.json", "incoming-test.json", "app-state.json"] {
            try data.write(to: root.appendingPathComponent(name))
        }
        let archive = try XCTUnwrap(ImportArchive.list(directory: root, phone: true).first { $0.title == "导入前备份" })
        try archive.delete(directory: root, phone: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("before-import-test.json").path))
        XCTAssertEqual(try ImportArchive.list(directory: root, phone: true).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("app-state.json").path))
        XCTAssertThrowsError(try archive.delete(directory: root.appendingPathComponent("another"), phone: true))
    }
    func testMacArchiveDeletionPreservesSiblingAndCurrentData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("backups/import")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try RecordExchange.encode(Database())
        try data.write(to: root.appendingPathComponent("sessions.json"))
        try data.write(to: folder.appendingPathComponent("before-import.json"))
        try data.write(to: folder.appendingPathComponent("incoming.json"))
        let archives = try ImportArchive.list(directory: root, phone: false)
        try archives[0].delete(directory: root, phone: false)
        XCTAssertEqual(try ImportArchive.list(directory: root, phone: false).count, 1)
        try archives[1].delete(directory: root, phone: false)
        XCTAssertEqual(try ImportArchive.list(directory: root, phone: false).count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions.json").path))
    }
    func testExportTimeSurvivesFileAndContentModification() throws {
        var database = Database()
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        database.source = ExchangeSource(device: "Mac", platform: "macOS", exportedAt: time)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: RecordExchange.encode(database)) as? [String: Any])
        let source = try XCTUnwrap(json["source"] as? [String: Any])
        XCTAssertEqual(source["exportedAtISO8601"] as? String, time.ISO8601Format())
        json["activity"] = "人工修改的内容"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("incoming-edited.json")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        let archive = try XCTUnwrap(ImportArchive.list(directory: root, phone: true).first)
        let decoded = try archive.read()
        XCTAssertEqual(decoded.source?.exportedAt, time)
        XCTAssertEqual(ExchangePreview.source(decoded), ExchangePreview.source(database))
    }
    func testMetadataRoundTripAndLegacyFallback() throws {
        var database = Database()
        database.source = ExchangeSource(device: "工作 Mac", platform: "macOS", exportedAt: Date(timeIntervalSince1970: 100))
        database.soundPreferences = SoundPreferences(FocusRoutineSettings())
        let decoded = try RecordExchange.decode(RecordExchange.encode(database))
        XCTAssertEqual(decoded.source, database.source)
        XCTAssertEqual(decoded.soundPreferences, database.soundPreferences)
        XCTAssertTrue(ExchangePreview.source(decoded).contains("工作 Mac"))
        XCTAssertTrue(ExchangePreview.source(Database()).contains("未知设备"))
    }
    func testUnchangedAndPurgedRecordsDoNotAppearAsAdditions() {
        let event = TimeEvent(kind: "健身", occurredAt: Date())
        let local = Database(events: [event])
        XCTAssertEqual(ExchangePreview.changes(local: local, incoming: local), [])
        XCTAssertEqual(ExchangePreview.changes(local: Database(purgedIDs: [event.id]), incoming: local), [])
        XCTAssertEqual(ExchangePreview.changes(local: Database(), incoming: local), ["时间标记：新增 1 个"])
        XCTAssertEqual(ExchangePreview.changes(local: local, incoming: Database(purgedIDs: [event.id])), ["时间标记：永久删除 1 个"])
    }
    func testSkippingParametersDoesNotPoisonRevisionLedger() throws {
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let local = FocusRoutineSettings()
        defaults.set(try JSONEncoder().encode(local), forKey: "focus-modes-v1")
        SharedPreferences.capture(defaults)
        var remote = local; remote.roundMinutes = 45
        var incoming = SharedSettings()
        incoming.entries["mode"] = PreferenceValue(value: try JSONEncoder().encode(ModeParameters(remote)).base64EncodedString(), modified: Date())
        incoming.entries["emoji/健身"] = PreferenceValue(value: "💪", modified: Date())
        SharedPreferences.apply(incoming, defaults: defaults, syncParameters: false)
        XCTAssertEqual(try JSONDecoder().decode(FocusRoutineSettings.self, from: XCTUnwrap(defaults.data(forKey: "focus-modes-v1"))).roundMinutes, 90)
        XCTAssertEqual(defaults.dictionary(forKey: "marker-emojis-v1")?["健身"] as? String, "💪")
        SharedPreferences.apply(incoming, defaults: defaults, syncParameters: true)
        XCTAssertEqual(try JSONDecoder().decode(FocusRoutineSettings.self, from: XCTUnwrap(defaults.data(forKey: "focus-modes-v1"))).roundMinutes, 45)
    }
    func testExistingImportFilesAreDiscoverable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("backups/old-import")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try RecordExchange.encode(Database())
        try data.write(to: folder.appendingPathComponent("incoming.json"))
        try data.write(to: folder.appendingPathComponent("before-import.json"))
        let archives = try ImportArchive.list(directory: root, phone: false)
        XCTAssertEqual(archives.count, 2)
        XCTAssertNoThrow(try archives[0].read())
        try data.write(to: root.appendingPathComponent("before-import-complete-old.json"))
        try data.write(to: root.appendingPathComponent("incoming-old.json"))
        XCTAssertEqual(try ImportArchive.list(directory: root, phone: true).count, 2)
    }
    func testLegacyPhoneBackupAndCompleteCopyAreNotDuplicated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data(#"{"version":5,"clock":{"accumulated":0},"sessions":[]}"#.utf8)
        try data.write(to: root.appendingPathComponent("before-import-legacy.json"))
        let archives = try ImportArchive.list(directory: root, phone: true)
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try archives[0].read().sessions.count, 0)
        try RecordExchange.encode(Database()).write(to: root.appendingPathComponent("before-import-complete-legacy.json"))
        XCTAssertEqual(try ImportArchive.list(directory: root, phone: true).count, 1)
    }
    func testSoundDirectoryRollsBackAsABatch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sounds = root.appendingPathComponent("sounds")
        try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
        let original = Data("original".utf8)
        try original.write(to: sounds.appendingPathComponent("old.wav"))
        try original.write(to: sounds.appendingPathComponent("library.json"))
        var restored = false
        let transaction = try SoundFileTransaction(directory: sounds, files: ["old.wav": Data(), "new.wav": Data()], index: Data()) { restored = true }
        try transaction.rollback()
        XCTAssertTrue(restored)
        XCTAssertEqual(try Data(contentsOf: sounds.appendingPathComponent("old.wav")), original)
        XCTAssertEqual(try Data(contentsOf: sounds.appendingPathComponent("library.json")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sounds.appendingPathComponent("new.wav").path))
    }
}
