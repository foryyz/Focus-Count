import XCTest
@testable import FocusCountCore

final class SharedPreferencesTests: XCTestCase {
    func testUnionClearAndOldImportDoesNotResurrect() throws {
        let aName = "sync-a-" + UUID().uuidString, bName = "sync-b-" + UUID().uuidString
        let a = UserDefaults(suiteName: aName)!, b = UserDefaults(suiteName: bName)!
        defer { a.removePersistentDomain(forName: aName); b.removePersistentDomain(forName: bName) }
        SharedPreferences.capture(a); SharedPreferences.capture(b)
        a.set(["冥想": "🧘"], forKey: "marker-emojis-v1")
        let first = SharedPreferences.capture(a, at: Date(timeIntervalSince1970: 10))
        b.set(["健身": "🏋️"], forKey: "marker-emojis-v1")
        SharedPreferences.capture(b, at: Date(timeIntervalSince1970: 11))
        SharedPreferences.apply(first, defaults: b)
        XCTAssertEqual(b.dictionary(forKey: "marker-emojis-v1") as? [String: String], ["冥想": "🧘", "健身": "🏋️"])
        SharedPreferences.apply(SharedPreferences.capture(b), defaults: a)
        a.set(["健身": "🏋️"], forKey: "marker-emojis-v1")
        let cleared = SharedPreferences.capture(a, at: Date(timeIntervalSince1970: 20))
        SharedPreferences.apply(cleared, defaults: b)
        SharedPreferences.apply(first, defaults: b)
        XCTAssertNil((b.dictionary(forKey: "marker-emojis-v1") as? [String: String])?["冥想"])
        XCTAssertEqual(SharedSettings.merge(first, cleared), SharedSettings.merge(cleared, first))
        XCTAssertTrue(SharedPreferences.validate(cleared))
    }
    func testModeSnapshotIsStableAndMalformedAssetsRejected() throws {
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var mode = FocusRoutineSettings(); mode.restSound = "Glass"; mode.focusSound = "Pop"
        defaults.set(try JSONEncoder().encode(mode), forKey: "focus-modes-v1")
        let first = SharedPreferences.capture(defaults)
        XCTAssertEqual(first, SharedPreferences.capture(defaults))
        let invalid = SharedSound(id: UUID().uuidString, name: "file", fileExtension: "../wav", data: Data([1]), modified: Date())
        var database = Database(); database.sounds = [invalid]
        XCTAssertThrowsError(try RecordExchange.decode(RecordExchange.encode(database)))
    }
    func testCategoriesAssignmentsColorsAndPrivacyMerge() throws {
        let name = UUID().uuidString, defaults = UserDefaults(suiteName: name)!, category = UUID()
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = SharedSettings()
        for (key, value) in ["category/" + category.uuidString: "学习", "assignment/阅读": category.uuidString, "focusColor/activity:阅读": "AABBCC", "markerColor/冥想": "249E91", "focus-target-hidden-v1": "true", "focus-target-total-hours-v1": "true"] {
            settings.entries[key] = PreferenceValue(value: value, modified: Date())
        }
        XCTAssertTrue(SharedPreferences.validate(settings))
        SharedPreferences.apply(settings, defaults: defaults)
        XCTAssertEqual(SharedPreferences.capture(defaults), settings)
        settings.entries["category/" + category.uuidString] = PreferenceValue(value: nil, modified: Date().addingTimeInterval(1))
        SharedPreferences.apply(settings, defaults: defaults)
        let data = try XCTUnwrap(defaults.data(forKey: "focus-analysis-appearance-v1"))
        let appearance = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((appearance["categories"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((appearance["assignments"] as? [String: Any])?.count, 0)
    }
}
