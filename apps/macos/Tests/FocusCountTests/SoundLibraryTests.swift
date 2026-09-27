import XCTest
import FocusCountCore
@testable import FocusCount

@MainActor final class SoundLibraryTests: XCTestCase {
    func testImportedSoundIsCopiedAndRenamePersists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Original.aiff")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"), to: source)
        let libraryRoot = root.appendingPathComponent("library")
        let library = SoundLibrary(directory: libraryRoot)
        try library.add(source)
        let sound = try XCTUnwrap(library.custom.first)
        try FileManager.default.removeItem(at: source)
        XCTAssertNotNil(library.sound(sound.id))
        library.rename(sound.id, to: " 我的铃声 ")
        let reopened = SoundLibrary(directory: libraryRoot)
        XCTAssertEqual(reopened.custom.first?.name, "我的铃声")
        XCTAssertNotNil(reopened.sound(sound.id))
        let invalid = root.appendingPathComponent("bad.mp3")
        try Data("not audio".utf8).write(to: invalid)
        XCTAssertThrowsError(try library.add(invalid))
        XCTAssertEqual(library.custom.count, 1)
        for preset in SoundLibrary.builtins { XCTAssertNotNil(library.sound(preset.id)) }
    }
    func testOlderModeSettingsDecodeAndSelectionsRoundTrip() throws {
        var settings = FocusRoutineSettings()
        let data = try JSONEncoder().encode(settings)
        let old = try JSONDecoder().decode(FocusRoutineSettings.self, from: data)
        XCTAssertNil(old.restSound)
        XCTAssertNil(old.focusSound)
        settings.restSound = "Ping"; settings.focusSound = UUID().uuidString
        XCTAssertEqual(try JSONDecoder().decode(FocusRoutineSettings.self, from: JSONEncoder().encode(settings)), settings)
    }
}
