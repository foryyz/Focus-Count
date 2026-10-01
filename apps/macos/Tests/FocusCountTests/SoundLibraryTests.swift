import XCTest
import SwiftUI
import AppKit
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
        XCTAssertNotNil(library.notice)
        let sound = try XCTUnwrap(library.custom.first)
        try FileManager.default.removeItem(at: source)
        XCTAssertNotNil(library.sound(sound.id))
        library.rename(sound.id, to: " 我的铃声 ")
        XCTAssertNotNil(library.notice)
        XCTAssertFalse(library.rename(sound.id, to: "  "))
        let reopened = SoundLibrary(directory: libraryRoot)
        XCTAssertEqual(reopened.custom.first?.name, "我的铃声")
        XCTAssertNotNil(reopened.sound(sound.id))
        let invalid = root.appendingPathComponent("bad.mp3")
        try Data("not audio".utf8).write(to: invalid)
        XCTAssertThrowsError(try library.add(invalid))
        XCTAssertEqual(library.custom.count, 1)
        for preset in SoundLibrary.builtins { XCTAssertNotNil(library.sound(preset.id)) }
    }
    func testDeleteSoundRemovesFileAndResetsSelectedAndActiveSounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("sounds")
        let library = SoundLibrary(directory: folder)
        try library.add(URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"))
        let sound = try XCTUnwrap(library.custom.first)
        let store = StudyStore(directory: root, observeSystem: false)
        var mode = FocusRoutineSettings(); mode.mode = .microBreak; mode.restSound = sound.id; mode.focusSound = sound.id
        XCTAssertTrue(store.setMode(mode)); store.toggle()
        XCTAssertTrue(store.deleteCustomSound(sound.id))
        XCTAssertNil(store.modeSettings.restSound)
        XCTAssertNil(store.modeSettings.focusSound)
        XCTAssertNil(store.database.focusRoutine?.settings.restSound)
        XCTAssertTrue(SoundLibrary(directory: folder).custom.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(sound.file!).path))
        XCTAssertNil(StudyStore(directory: root, observeSystem: false).modeSettings.restSound)
        XCTAssertFalse(store.deleteCustomSound("Glass"))
    }
    func testDeletionRollbackRestoresFileAndLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SoundLibrary(directory: root)
        try library.add(URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"))
        let sound = try XCTUnwrap(library.custom.first)
        let transaction = try library.stageDeletion(sound.id)
        XCTAssertTrue(library.custom.isEmpty)
        try transaction.rollback()
        XCTAssertEqual(library.custom.first?.id, sound.id)
        XCTAssertNotNil(library.sound(sound.id))
    }
    func testSoundSettingsFeedbackRender() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        try store.soundLibrary.add(URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"))
        let sound = try XCTUnwrap(store.soundLibrary.custom.first)
        XCTAssertTrue(store.soundLibrary.rename(sound.id, to: "我的自定义提示音"))
        let host = NSHostingView(rootView: SoundSettingsView(store: store).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 460)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/fc-sound-settings.png"))
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
