import XCTest
@testable import FocusCountCore

final class PreferenceStorageTests: XCTestCase {
    func testUnchangedCaptureDoesNotRewriteLedgerOrPublish() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = FilePreferences(directory: root)
        preferences.set(Dictionary(uniqueKeysWithValues: (0..<12).map { ("event-\($0)", "📚") }), forKey: "marker-emojis-v1")
        let captured = SharedPreferences.capture(preferences)
        let revision = preferences.revision
        for _ in 0..<20 { XCTAssertEqual(SharedPreferences.capture(preferences), captured) }
        XCTAssertEqual(preferences.revision, revision)
    }
    func testLegacyKeysAreRemovedWithoutTouchingUnrelatedPreferences() {
        let suite = "RetiredPreferences-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(), forKey: "focus-modes-v1")
        defaults.set(true, forKey: SyncPreferences.soundsKey)
        defaults.set("keep", forKey: "unrelated")
        FilePreferences.discardLegacyDefaults(defaults)
        XCTAssertNil(defaults.object(forKey: "focus-modes-v1"))
        XCTAssertNil(defaults.object(forKey: SyncPreferences.soundsKey))
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
    }
    func testRoundTripAndDirectoryRemovalResetEveryValue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilePreferences(directory: root)
        XCTAssertNil(store.object(forKey: "focus-modes-v1"))
        var mode = FocusRoutineSettings(); mode.minimumMinutes = 8; mode.maximumMinutes = 9
        store.set(try JSONEncoder().encode(mode), forKey: "focus-modes-v1")
        store.set(["reading": "📚"], forKey: "marker-emojis-v1")
        store.set(true, forKey: SyncPreferences.soundsKey)
        store.set(true, forKey: "focus-target-hidden-v1")
        SharedPreferences.capture(store)
        let loaded = FilePreferences(directory: root)
        XCTAssertEqual(try JSONDecoder().decode(FocusRoutineSettings.self, from: XCTUnwrap(loaded.data(forKey: "focus-modes-v1"))), mode)
        XCTAssertEqual(loaded.dictionary(forKey: "marker-emojis-v1") as? [String: String], ["reading": "📚"])
        XCTAssertTrue(loaded.bool(forKey: SyncPreferences.soundsKey))
        XCTAssertEqual(SharedPreferences.capture(loaded), SharedPreferences.capture(store))
        try FileManager.default.removeItem(at: root)
        let empty = FilePreferences(directory: root)
        XCTAssertNil(empty.data(forKey: "focus-modes-v1"))
        XCTAssertFalse(empty.bool(forKey: SyncPreferences.soundsKey))
        XCTAssertNil(empty.object(forKey: "focus-target-hidden-v1"))
        XCTAssertTrue(SharedPreferences.capture(empty).entries.isEmpty)
    }
    func testCorruptFileIsNeverOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytes = Data("broken".utf8), file = root.appendingPathComponent("settings.plist")
        try bytes.write(to: file)
        let store = FilePreferences(directory: root)
        XCTAssertNotNil(store.error)
        store.set(true, forKey: "flag")
        SharedPreferences.capture(store)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testFailedWriteDoesNotChangeInMemoryValues() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        let store = FilePreferences(directory: file)
        store.set(true, forKey: "flag")
        XCTAssertNotNil(store.error)
        XCTAssertNil(store.object(forKey: "flag"))
    }
    func testExchangeAppliesToFileSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FilePreferences(directory: root)
        var incoming = SharedSettings()
        incoming.entries["emoji/reading"] = PreferenceValue(value: "📚", modified: Date())
        incoming.entries["focus-target-total-hours-v1"] = PreferenceValue(value: "true", modified: Date())
        SharedPreferences.apply(incoming, defaults: store)
        let reloaded = FilePreferences(directory: root)
        XCTAssertTrue(reloaded.bool(forKey: "focus-target-total-hours-v1"))
        XCTAssertEqual(reloaded.dictionary(forKey: "marker-emojis-v1") as? [String: String], ["reading": "📚"])
    }
}
