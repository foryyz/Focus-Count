import XCTest
import FocusCountCore
@testable import FocusCount

@MainActor final class FocusModeTests: XCTestCase {
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
    func testCancelAndTimerTransferClearRoutine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(directory: root, observeSystem: false)
        var settings = FocusRoutineSettings(); settings.mode = .microBreak
        XCTAssertTrue(store.setMode(settings)); store.toggle()
        XCTAssertNotNil(store.database.focusRoutine)
        let snapshot = try RecordExchange.decode(store.export())
        XCTAssertNil(snapshot.focusRoutine)
        XCTAssertTrue(store.importRecords(snapshot, syncTimer: true))
        XCTAssertNil(store.database.focusRoutine)
        XCTAssertTrue(store.cancelTimer())
        XCTAssertNil(store.database.focusRoutine)
        XCTAssertNil(store.database.draft.startedAt)
    }
}
