import XCTest
import FocusCountCore
@testable import FocusCount

final class DirectorySettingsTests: XCTestCase {
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
