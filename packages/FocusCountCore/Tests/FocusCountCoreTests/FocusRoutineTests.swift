import XCTest
@testable import FocusCountCore

final class FocusRoutineTests: XCTestCase {
    func settings() -> FocusRoutineSettings {
        var value = FocusRoutineSettings(); value.mode = .microBreak
        value.minimumMinutes = 1; value.maximumMinutes = 1; value.roundMinutes = 3; value.restMinutes = 1
        return value
    }
    func testCycleExcludesBreaksAndStopsAtReady() {
        var state = FocusRoutine(settings: settings())
        XCTAssertEqual(state.advance(60), 60)
        XCTAssertEqual(state.phase, .microRest)
        XCTAssertEqual(state.advance(10), 0)
        XCTAssertEqual(state.phase, .focus)
        XCTAssertEqual(state.advance(110), 100)
        XCTAssertEqual(state.phase, .longRest)
        XCTAssertEqual(state.advance(600), 0)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.advance(600), 0)
        state.nextRound()
        XCTAssertEqual(state.phase, .focus)
        XCTAssertEqual(state.roundRemaining, 180)
    }
    func testSuspensionAndSkipping() {
        var state = FocusRoutine(settings: settings())
        state.advance(60)
        state.suspended = true
        XCTAssertEqual(state.advance(90), 0)
        XCTAssertEqual(state.remaining, 10)
        state.skipRest()
        XCTAssertTrue(state.suspended)
        state.suspended = false
        XCTAssertEqual(state.advance(120), 110)
        XCTAssertEqual(state.phase, .longRest)
    }
    func testRandomBoundsRoundDeadlineAndPersistence() throws {
        var settings = FocusRoutineSettings(); settings.mode = .microBreak
        XCTAssertEqual(FocusRoutine(settings: settings, random: 0).remaining, 180)
        XCTAssertEqual(FocusRoutine(settings: settings, random: 1).remaining, 300)
        settings.roundMinutes = 1
        var state = FocusRoutine(settings: settings, random: 1)
        XCTAssertEqual(state.advance(65), 60)
        XCTAssertEqual(state.phase, .longRest)
        XCTAssertEqual(state.remaining, 1195)
        XCTAssertEqual(try JSONDecoder().decode(FocusRoutine.self, from: JSONEncoder().encode(state)), state)
    }
    func testValidation() {
        var settings = FocusRoutineSettings()
        settings.maximumMinutes = 2
        XCTAssertFalse(settings.isValid)
        settings.minimumMinutes = 0
        XCTAssertFalse(settings.isValid)
        var state = FocusRoutine(settings: self.settings())
        state.remaining = -.infinity
        XCTAssertFalse(state.isValid)
    }
}
