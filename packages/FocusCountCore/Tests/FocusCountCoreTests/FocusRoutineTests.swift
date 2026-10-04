import XCTest
@testable import FocusCountCore

final class FocusRoutineTests: XCTestCase {
    func testModeVolumesAreIndependentPersistAndMigrate() throws {
        var settings = FocusRoutineSettings()
        settings.setVolume(0.2, for: .standard)
        settings.setVolume(0.6, for: .microBreak)
        settings.setVolume(0.9, for: .course)
        XCTAssertEqual(settings.volume, 0.2)
        settings.mode = .course
        XCTAssertEqual(settings.volume, 0.9)
        settings.volume = 0.8
        XCTAssertEqual(settings.standardVolume, 0.2)
        XCTAssertEqual(settings.microBreakVolume, 0.6)
        XCTAssertEqual(try JSONDecoder().decode(FocusRoutineSettings.self, from: JSONEncoder().encode(settings)), settings)
        let reset = settings.restoringDefaults(for: .course)
        XCTAssertEqual(reset.courseVolume, 0.4)
        XCTAssertEqual(reset.standardVolume, 0.2)
        XCTAssertEqual(reset.microBreakVolume, 0.6)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        for key in ["standardVolume", "microBreakVolume", "courseVolume"] { old.removeValue(forKey: key) }
        old["volume"] = 0.7
        let migrated = try JSONDecoder().decode(FocusRoutineSettings.self, from: JSONSerialization.data(withJSONObject: old))
        for mode in FocusMode.allCases { XCTAssertEqual(migrated.volume(for: mode), 0.7) }
        settings.standardVolume = .nan
        XCTAssertFalse(settings.isValid)
    }
    func testIndependentVolumesSyncOnlyWithSoundPreferences() throws {
        var local = FocusRoutineSettings(); local.mode = .course
        local.standardVolume = 0.1; local.microBreakVolume = 0.2; local.courseVolume = 0.3
        var remote = FocusRoutineSettings()
        remote.standardVolume = 0.9; remote.microBreakVolume = 0.8; remote.courseVolume = 0.7
        XCTAssertEqual(ModeParameters(remote).applying(to: local).courseVolume, 0.3)
        let audio = try JSONDecoder().decode(SoundPreferences.self, from: JSONEncoder().encode(SoundPreferences(remote)))
        let applied = audio.applying(to: local)
        XCTAssertEqual(applied.mode, .course)
        for mode in FocusMode.allCases { XCTAssertEqual(applied.volume(for: mode), remote.volume(for: mode)) }
        let old = try JSONDecoder().decode(SoundPreferences.self, from: Data(#"{"volume":0.5}"#.utf8))
        for mode in FocusMode.allCases { XCTAssertEqual(old.applying(to: local).volume(for: mode), 0.5) }
        var invalid = audio; invalid.courseVolume = 2
        XCTAssertFalse(invalid.isValid)
    }
    func testCourseCyclesExcludeBreaksIncludingLongAbsence() throws {
        var settings = FocusRoutineSettings(); settings.mode = .course
        var routine = FocusRoutine(settings: settings)
        XCTAssertEqual(routine.remaining, 3600)
        XCTAssertEqual(routine.advance(3600), 3600)
        XCTAssertEqual(routine.phase, .longRest)
        XCTAssertEqual(routine.remaining, 600)
        XCTAssertEqual(routine.advance(600), 0)
        XCTAssertEqual(routine.phase, .focus)
        XCTAssertEqual(routine.advance(4200 * 1000 + 3630), 3600 * 1001)
        XCTAssertEqual(routine.phase, .longRest)
        XCTAssertEqual(routine.remaining, 570)
        XCTAssertTrue(routine.isValid)
        XCTAssertEqual(try JSONDecoder().decode(FocusRoutine.self, from: JSONEncoder().encode(routine)), routine)
        routine.suspended = true
        XCTAssertEqual(routine.advance(600), 0)
        routine.skipRest()
        XCTAssertTrue(routine.suspended)
        XCTAssertEqual(routine.phase, .focus)
        routine.suspended = false
        XCTAssertEqual(routine.advance(30), 30)
    }
    func testOldSettingsAndParametersKeepCourseDefaultsAndLocalValues() throws {
        let data = try JSONEncoder().encode(FocusRoutineSettings())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "lessonMinutes"); json.removeValue(forKey: "classBreakMinutes")
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(FocusRoutineSettings.self, from: old)
        XCTAssertEqual(decoded.lessonMinutes, 60); XCTAssertEqual(decoded.classBreakMinutes, 10)
        var local = decoded; local.lessonMinutes = 45; local.classBreakMinutes = 15
        let parameters = try JSONDecoder().decode(ModeParameters.self, from: old)
        XCTAssertEqual(parameters.applying(to: local).lessonMinutes, 45)
        XCTAssertEqual(parameters.applying(to: local).classBreakMinutes, 15)
        local.classStartSound = "Ping"; local.classEndSound = "Hero"; local.startSound = "Tink"; local.pauseSound = "Submarine"
        let audio = try JSONDecoder().decode(SoundPreferences.self, from: JSONEncoder().encode(SoundPreferences(local)))
        XCTAssertTrue(audio.isValid)
        XCTAssertEqual(SoundPreferences(audio.applying(to: decoded)), SoundPreferences(local))
        let oldAudio = try JSONDecoder().decode(SoundPreferences.self, from: Data(#"{"volume":0.4,"restSound":"Glass"}"#.utf8))
        XCTAssertEqual(oldAudio.applying(to: local).classStartSound, "Ping")
        XCTAssertEqual(oldAudio.applying(to: local).pauseSound, "Submarine")
        XCTAssertNil(SoundPreferences(decoded).applying(to: local).pauseSound)
        XCTAssertNil(local.removingSound("Tink").startSound)
        local.lessonMinutes = 0
        XCTAssertFalse(local.isValid)
    }
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
