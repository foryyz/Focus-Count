import Foundation
import Combine

/// Common settings interface: iPhone retains UserDefaults; Mac uses a file in its data directory.
public protocol PreferenceStorage: AnyObject {
    func object(forKey key: String) -> Any?
    func data(forKey key: String) -> Data?
    func dictionary(forKey key: String) -> [String: Any]?
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}
extension UserDefaults: PreferenceStorage {}

public enum ApplicationPreferences {
    public static var current: any PreferenceStorage {
        #if os(macOS)
        return FilePreferences.shared
        #else
        return UserDefaults.standard
        #endif
    }
}

/// Atomic, property-list settings. Never reads a system preference domain or another directory.
public final class FilePreferences: NSObject, ObservableObject, PreferenceStorage {
    public static let shared = FilePreferences(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FocusCount", isDirectory: true))
    /// Remove only retired app-owned keys, never OS preferences or another app's domain.
    public static func discardLegacyDefaults(_ defaults: UserDefaults) {
        for key in ["focus-modes-v1", "marker-colors-v1", "marker-emojis-v1", "focus-analysis-appearance-v1",
                    "focus-target-date-v1", "focus-target-hidden-v1", "focus-target-total-hours-v1", "shared-settings-v1",
                    SyncPreferences.soundsKey, SyncPreferences.parametersKey,
                    "NSWindow Frame FocusCountAnalysisWindow", "NSWindow Frame FocusCountMarkerWindowWide"] {
            defaults.removeObject(forKey: key)
        }
    }
    public let file: URL
    @Published public private(set) var error: String?
    @Published public private(set) var revision = 0
    private var values: [String: Any] = [:]
    private var readable = true

    public init(directory: URL) {
        file = directory.appendingPathComponent("settings.plist")
        super.init()
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let bytes = try Data(contentsOf: file)
            guard let root = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
                  root["version"] as? Int == 1, let saved = root["values"] as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            values = saved
        } catch {
            readable = false
            self.error = "无法读取设置，已保留原文件并停止设置写入：\(error.localizedDescription)"
        }
    }
    public func object(forKey key: String) -> Any? { values[key] }
    public func data(forKey key: String) -> Data? { values[key] as? Data }
    public func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    public func bool(forKey key: String) -> Bool { (values[key] as? NSNumber)?.boolValue ?? false }
    public func set(_ value: Any?, forKey key: String) {
        guard readable else { return }
        var next = values
        next[key] = value
        guard !NSDictionary(dictionary: values).isEqual(to: next) else { return }
        do {
            let bytes = try PropertyListSerialization.data(fromPropertyList: ["version": 1, "values": next], format: .xml, options: 0)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: file, options: .atomic)
            values = next
            error = nil
            revision += 1
        } catch { self.error = "无法保存设置：\(error.localizedDescription)" }
    }
    public func removeObject(forKey key: String) { set(nil, forKey: key) }
}
