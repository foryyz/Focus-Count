import Foundation

/// Metadata describes the file's creation, not a live connection to its source.
public struct ExchangeSource: Codable, Equatable {
    public var exportedAt: Date
    public var device: String
    public var platform: String
    public init(device: String, platform: String, exportedAt: Date = Date()) {
        self.device = device; self.platform = platform; self.exportedAt = exportedAt
    }
    private enum CodingKeys: String, CodingKey { case exportedAt, device, platform, exportedAtISO8601 }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        device = try values.decode(String.self, forKey: .device)
        platform = try values.decode(String.self, forKey: .platform)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(exportedAt, forKey: .exportedAt)
        try values.encode(device, forKey: .device)
        try values.encode(platform, forKey: .platform)
        // exportedAt remains authoritative; this companion string is for people reading JSON.
        try values.encode(exportedAt.ISO8601Format(), forKey: .exportedAtISO8601)
    }

}

public struct SoundPreferences: Codable, Equatable {
    public var restSound: String?
    public var focusSound: String?
    public var volume: Double
    public init(_ settings: FocusRoutineSettings) {
        restSound = settings.restSound; focusSound = settings.focusSound; volume = settings.volume
    }
    public var isValid: Bool {
        let builtins = ["Glass", "Pop", "Hero", "Ping", "Tink", "Submarine"]
        return volume.isFinite && (0...1).contains(volume) && [restSound, focusSound].allSatisfy {
            $0 == nil || builtins.contains($0!) || UUID(uuidString: $0!) != nil
        }
    }
    public func applying(to local: FocusRoutineSettings) -> FocusRoutineSettings {
        var result = local
        result.restSound = restSound; result.focusSound = focusSound; result.volume = volume
        return result
    }
}

public enum ExchangePreview {
    public static let rules = "相同记录去重，较新修改生效，旧修改保留；永久删除不会复活。导入前自动备份。"
    public static func source(_ database: Database) -> String {
        let date = database.source?.exportedAt
        let time = date?.formatted(date: .abbreviated, time: .standard) ?? "未知时间"
        let device = database.source.map { "\($0.device) · \($0.platform)" } ?? "未知设备"
        return "导出于 \(time)\n来源：\(device)"
    }
    /// Reports differences in resulting data, not totals of unchanged records.
    public static func changes(local: Database, incoming: Database, syncParameters: Bool = true) -> [String] {
        let purged = (local.purgedIDs ?? []).union(incoming.purgedIDs ?? [])
        let sessions = RecordExchange.merge(local: local.sessions, incoming: incoming.sessions, purgedIDs: purged)
        let events = RecordExchange.mergeEvents(local: local.events ?? [], incoming: incoming.events ?? [], purgedIDs: purged)
        var lines: [String] = []
        func counts<T: Identifiable>(_ before: [T], _ after: [T], label: String, equal: (T,T) -> Bool) where T.ID == UUID {
            let old = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
            let newIDs = Set(after.map(\.id))
            let added = after.filter { old[$0.id] == nil }.count
            let changed = after.filter { item in old[item.id].map { !equal($0, item) } ?? false }.count
            let removed = before.filter { !newIDs.contains($0.id) }.count
            var parts: [String] = []
            if added > 0 { parts.append("新增 \(added) 个") }
            if changed > 0 { parts.append("更新 \(changed) 个") }
            if removed > 0 { parts.append("永久删除 \(removed) 个") }
            if !parts.isEmpty { lines.append(label + "：" + parts.joined(separator: "，")) }
        }
        counts(local.sessions, sessions, label: "专注记录") { SessionSnapshot($0) == SessionSnapshot($1) }
        counts(local.events ?? [], events, label: "时间标记") { $0 == $1 }
        let oldVersions = Set(local.sessions.flatMap { ($0.history ?? []).map(\.id) })
        let newVersions = Set(sessions.flatMap { ($0.history ?? []).map(\.id) })
        let addedVersions = newVersions.subtracting(oldVersions).count
        let deletedVersions = oldVersions.subtracting(newVersions).count
        if addedVersions > 0 { lines.append("新增 \(addedVersions) 个记录历史版本") }
        if deletedVersions > 0 { lines.append("删除 \(deletedVersions) 个记录历史版本") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if (try? encoder.encode(GoalSnapshot.merge(local.goal, incoming.goal))) != (try? encoder.encode(local.goal)) { lines.append("更新目标日期") }
        let before = local.sharedSettings ?? SharedSettings()
        var selected = incoming.sharedSettings ?? SharedSettings()
        if !syncParameters { selected.entries.removeValue(forKey: "mode") }
        let merged = SharedSettings.merge(before, selected)
        let keys = merged.entries.keys.filter { before.entries[$0]?.value != merged.entries[$0]?.value }
        let appearance = keys.filter { $0 != "mode" }.count
        if appearance > 0 { lines.append("更新 \(appearance) 项个性化设置") }
        if keys.contains("mode") { lines.append("更新模式数值参数") }
        return lines
    }
}

/// Discover existing on-disk imports too; no migration or new index is required.
public struct ImportArchive: Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let date: Date
    public let title: String
    public static func list(directory: URL, phone: Bool) throws -> [Self] {
        let folder = phone ? directory : directory.appendingPathComponent("backups")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        var files: [URL] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        for item in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) {
            let info = try item.resourceValues(forKeys: Set(keys))
            guard info.isSymbolicLink != true else { continue }
            if phone {
                let name = item.lastPathComponent
                if name.hasPrefix("before-import-complete-") || name.hasPrefix("incoming-") { files.append(item) }
                else if name.hasPrefix("before-import-") {
                    let complete = folder.appendingPathComponent(name.replacingOccurrences(of: "before-import-", with: "before-import-complete-"))
                    if !FileManager.default.fileExists(atPath: complete.path) { files.append(item) }
                }
            } else if info.isDirectory == true {
                for name in ["before-import.json", "incoming.json"] {
                    let url = item.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: url.path) { files.append(url) }
                }
            }
        }
        return try files.filter { $0.pathExtension == "json" }.map {
            let info = try $0.resourceValues(forKeys: Set(keys))
            return Self(url: $0, date: info.contentModificationDate ?? .distantPast,
                        title: $0.lastPathComponent.hasPrefix("incoming") ? "导入文件" : "导入前备份")
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    /// Only entries discovered under this application's archive directory can be deleted.
    public func delete(directory: URL, phone: Bool) throws {
        guard try Self.list(directory: directory, phone: phone).contains(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        if phone, url.lastPathComponent.hasPrefix("before-import-complete-") {
            let legacy = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent.replacingOccurrences(of: "before-import-complete-", with: "before-import-"))
            if fm.fileExists(atPath: legacy.path) { try fm.removeItem(at: legacy) }
        }
        try fm.removeItem(at: url)
        if !phone, (try? fm.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).isEmpty) == true {
            try? fm.removeItem(at: url.deletingLastPathComponent())
        }
    }
    public func read() throws -> Database {
        let data = try Data(contentsOf: url)
        do { return try RecordExchange.decode(data) }
        catch {
            // Older iPhone backups used PhoneState, not the interchange container.
            struct LegacyPhoneBackup: Decodable {
                var version: Int
                var clock: MobileClock
                var sessions: [StudySession]
                var events: [TimeEvent]?
                var purgedIDs: Set<UUID>?
                var goal: GoalSnapshot?
            }
            guard let legacy = try? JSONDecoder().decode(LegacyPhoneBackup.self, from: data), legacy.clock.isValid else { throw error }
            let database = Database(version: legacy.version, events: legacy.events, purgedIDs: legacy.purgedIDs, sessions: legacy.sessions, goal: legacy.goal)
            return try RecordExchange.decode(RecordExchange.encode(database))
        }
    }
}

/// Keeps the original directory until the caller commits the associated records.
public final class SoundFileTransaction {
    private let directory: URL
    private let backup: URL
    private let hadOriginal: Bool
    private var finished = false
    private let restoreIndex: () -> Void
    public init(directory: URL, files: [String: Data], index: Data, restoreIndex: @escaping () -> Void) throws {
        self.directory = directory; self.restoreIndex = restoreIndex
        let fm = FileManager.default, parent = directory.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".sounds-stage-" + UUID().uuidString)
        backup = parent.appendingPathComponent(".sounds-backup-" + UUID().uuidString)
        hadOriginal = fm.fileExists(atPath: directory.path)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        if hadOriginal { try fm.copyItem(at: directory, to: staging) }
        else { try fm.createDirectory(at: staging, withIntermediateDirectories: true) }
        for (name, data) in files {
            guard URL(fileURLWithPath: name).lastPathComponent == name else { throw CocoaError(.fileWriteInvalidFileName) }
            try data.write(to: staging.appendingPathComponent(name), options: .atomic)
        }
        try index.write(to: staging.appendingPathComponent("library.json"), options: .atomic)
        if hadOriginal { try fm.moveItem(at: directory, to: backup) }
        do { try fm.moveItem(at: staging, to: directory) }
        catch {
            if hadOriginal { try? fm.moveItem(at: backup, to: directory) }
            throw error
        }
    }
    public func finish() { finished = true; try? FileManager.default.removeItem(at: backup) }
    public func rollback() throws {
        guard !finished else { return }
        try FileManager.default.removeItem(at: directory)
        if hadOriginal { try FileManager.default.moveItem(at: backup, to: directory) }
        restoreIndex(); finished = true
    }
}
