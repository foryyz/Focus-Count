import Foundation

public struct PreferenceValue: Codable, Equatable {
    public var value: String?
    public var modified: Date
    public init(value: String?, modified: Date) { self.value = value; self.modified = modified }
}
public struct SharedSettings: Codable, Equatable {
    public var entries: [String: PreferenceValue] = [:]
    public init() {}
    public static func merge(_ left: Self, _ right: Self) -> Self {
        var result = left
        for (key, item) in right.entries {
            if let old = result.entries[key], old.modified > item.modified || (old.modified == item.modified && (old.value ?? "") >= (item.value ?? "")) { continue }
            result.entries[key] = item
        }
        return result
    }
}

/// Only timing numbers travel; mode selection and all audio preferences stay local.
public struct ModeParameters: Codable, Equatable {
    public var minimumMinutes: Int
    public var maximumMinutes: Int
    public var microSeconds: Int
    public var roundMinutes: Int
    public var restMinutes: Int
    public init(_ settings: FocusRoutineSettings) {
        minimumMinutes = settings.minimumMinutes; maximumMinutes = settings.maximumMinutes
        microSeconds = settings.microSeconds; roundMinutes = settings.roundMinutes; restMinutes = settings.restMinutes
    }
    public func applying(to local: FocusRoutineSettings) -> FocusRoutineSettings {
        var result = local
        result.minimumMinutes = minimumMinutes; result.maximumMinutes = maximumMinutes
        result.microSeconds = microSeconds; result.roundMinutes = roundMinutes; result.restMinutes = restMinutes
        return result
    }
}

/// Per-item revision ledger; nil values are explicit removals, not missing data.
public enum SharedPreferences {
    public static let changed = Notification.Name("FocusCountSharedPreferencesChanged")
    private static let ledger = "shared-settings-v1"
    private struct Category: Codable { var id: UUID; var name: String }
    private struct Appearance: Codable {
        var categories: [Category] = []; var assignments: [String: UUID] = [:]; var colors: [String: String] = [:]
    }
    private static func canonical<T: Encodable>(_ value: T) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value) }
    private static func current(_ defaults: UserDefaults) -> [String: String] {
        var result: [String: String] = [:]
        for (key, prefix) in [("marker-colors-v1", "markerColor/"), ("marker-emojis-v1", "emoji/")] {
            for (name, value) in defaults.dictionary(forKey: key) as? [String: String] ?? [:] { result[prefix + name] = value }
        }
        if let data = defaults.data(forKey: "focus-analysis-appearance-v1"), let appearance = try? JSONDecoder().decode(Appearance.self, from: data) {
            for item in appearance.categories { result["category/" + item.id.uuidString] = item.name }
            for (name, id) in appearance.assignments { result["assignment/" + name] = id.uuidString }
            for (name, value) in appearance.colors { result["focusColor/" + name] = value }
        }
        for key in ["focus-target-hidden-v1", "focus-target-total-hours-v1"] where defaults.object(forKey: key) != nil { result[key] = defaults.bool(forKey: key) ? "true" : "false" }
        if let data = defaults.data(forKey: "focus-modes-v1"), let value = try? JSONDecoder().decode(FocusRoutineSettings.self, from: data), let canonical = try? canonical(ModeParameters(value)) { result["mode"] = canonical.base64EncodedString() }
        return result
    }
    private static func numbersOnly(_ settings: SharedSettings) -> SharedSettings {
        var result = settings
        if let text = result.entries["mode"]?.value, let data = Data(base64Encoded: text),
           let parameters = try? JSONDecoder().decode(ModeParameters.self, from: data), let value = try? canonical(parameters) {
            result.entries["mode"]?.value = value.base64EncodedString()
        }
        return result
    }
    @discardableResult public static func capture(_ defaults: UserDefaults = .standard, at date: Date = Date()) -> SharedSettings {
        let saved = defaults.data(forKey: ledger).flatMap { try? JSONDecoder().decode(SharedSettings.self, from: $0) }
        var result = numbersOnly(saved ?? SharedSettings())
        let values = current(defaults)
        for key in Set(result.entries.keys).union(values.keys) {
            if let old = result.entries[key], old.value == values[key] { continue }
            let time = saved == nil ? Date.distantPast : max(date, (result.entries[key]?.modified ?? .distantPast).addingTimeInterval(0.001))
            result.entries[key] = PreferenceValue(value: values[key], modified: time)
        }
        if let data = try? JSONEncoder().encode(result) { defaults.set(data, forKey: ledger) }
        return result
    }
    public static func validate(_ value: SharedSettings) -> Bool {
        value.entries.allSatisfy { key, entry in
            guard key.count <= 2000, entry.modified.timeIntervalSince1970.isFinite else { return false }
            let known = key.hasPrefix("emoji/") || key.hasPrefix("markerColor/") || key.hasPrefix("category/") || key.hasPrefix("assignment/") || key.hasPrefix("focusColor/") || ["mode", "focus-target-hidden-v1", "focus-target-total-hours-v1"].contains(key)
            guard known else { return false }
            guard let value = entry.value else { return true }
            if key == "mode" { return Data(base64Encoded: value).flatMap { try? JSONDecoder().decode(ModeParameters.self, from: $0) }?.applying(to: FocusRoutineSettings()).isValid == true }
            if key.hasPrefix("markerColor/") || key.hasPrefix("focusColor/") { return value.count == 6 && UInt32(value, radix: 16) != nil }
            if key.hasPrefix("assignment/") { return UUID(uuidString: value) != nil }
            if key.hasPrefix("category/") { return UUID(uuidString: String(key.dropFirst(9))) != nil && !value.isEmpty && value.count <= 1000 }
            if key.hasPrefix("emoji/") { return value.count <= 1 }
            return value == "true" || value == "false"
        }
    }
    public static func apply(_ incoming: SharedSettings, defaults: UserDefaults = .standard) {
        let merged = SharedSettings.merge(capture(defaults), numbersOnly(incoming))
        var colors: [String: String] = [:], emojis: [String: String] = [:], appearance = Appearance()
        for (key, item) in merged.entries {
            guard let value = item.value else { continue }
            if key.hasPrefix("markerColor/") { colors[String(key.dropFirst(12))] = value }
            else if key.hasPrefix("emoji/") { emojis[String(key.dropFirst(6))] = value }
            else if key.hasPrefix("category/"), let id = UUID(uuidString: String(key.dropFirst(9))) { appearance.categories.append(Category(id: id, name: value)) }
            else if key.hasPrefix("assignment/"), let id = UUID(uuidString: value) { appearance.assignments[String(key.dropFirst(11))] = id }
            else if key.hasPrefix("focusColor/") { appearance.colors[String(key.dropFirst(11))] = value }
        }
        appearance.categories.sort { $0.id.uuidString < $1.id.uuidString }
        appearance.assignments = appearance.assignments.filter { _, id in appearance.categories.contains { $0.id == id } }
        defaults.set(colors, forKey: "marker-colors-v1"); defaults.set(emojis, forKey: "marker-emojis-v1")
        if let data = try? JSONEncoder().encode(appearance) { defaults.set(data, forKey: "focus-analysis-appearance-v1") }
        for key in ["focus-target-hidden-v1", "focus-target-total-hours-v1"] {
            if let item = merged.entries[key] { if let value = item.value { defaults.set(value == "true", forKey: key) } else { defaults.removeObject(forKey: key) } }
        }
        if let text = merged.entries["mode"]?.value, let data = Data(base64Encoded: text),
           let parameters = try? JSONDecoder().decode(ModeParameters.self, from: data) {
            let local = defaults.data(forKey: "focus-modes-v1").flatMap { try? JSONDecoder().decode(FocusRoutineSettings.self, from: $0) } ?? FocusRoutineSettings()
            if let data = try? canonical(parameters.applying(to: local)) { defaults.set(data, forKey: "focus-modes-v1") }
        }
        if let data = try? JSONEncoder().encode(merged) { defaults.set(data, forKey: ledger) }
        NotificationCenter.default.post(name: changed, object: defaults)
    }
}

public struct SharedSound: Codable {
    public var id: String
    public var name: String
    public var fileExtension: String
    public var data: Data
    public var modified: Date
    public init(id: String, name: String, fileExtension: String, data: Data, modified: Date) { self.id = id; self.name = name; self.fileExtension = fileExtension; self.data = data; self.modified = modified }
    public var isValid: Bool { UUID(uuidString: id) != nil && !name.isEmpty && name.count <= 1000 && !data.isEmpty && data.count <= 50 * 1024 * 1024 && !fileExtension.isEmpty && fileExtension.count <= 10 && fileExtension.allSatisfy { $0.isASCII && $0.isLetter || $0.isNumber } && modified.timeIntervalSince1970.isFinite }
}
