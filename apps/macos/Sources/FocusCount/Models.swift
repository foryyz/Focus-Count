import Foundation
import FocusCountCore

enum Storage {
    // Resolve from the executable, never the shell's working directory.
    // Both dist/macos/FocusCount.app and SwiftPM's .build live below the root.
    static func projectDirectory(executable: URL) throws -> URL {
        var path = executable.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent().path
        while !path.isEmpty {
            let candidate = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".focuscount-root").path) { return candidate }
            let parent = (path as NSString).deletingLastPathComponent
            if parent.count >= path.count { break }
            path = parent
        }
        throw NSError(domain: "FocusCount.Storage", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "找不到项目根目录，请将应用放在项目的 dist/macos 目录中，并保留 .focuscount-root 文件。"])
    }
    static var directory: URL { legacyDirectory }
    static var legacyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusCount", isDirectory: true)
    }

    // Optional discovery for upgrading an existing checkout, never required to launch.
    static func migrateProjectData(executable: URL, to destination: URL) throws {
        guard let root = try? projectDirectory(executable: executable) else { return }
        try migrateLegacyData(from: root.appendingPathComponent("data"), to: destination)
    }

    static func migrateLegacyData(from sourceDirectory: URL, to destination: URL) throws {
        let fm = FileManager.default
        let source = sourceDirectory.appendingPathComponent("sessions.json")
        let target = destination.appendingPathComponent("sessions.json")
        let marker = destination.appendingPathComponent("project-storage-migration.json")
        guard source.standardizedFileURL != target.standardizedFileURL,
              fm.fileExists(atPath: source.path), !fm.fileExists(atPath: marker.path) else { return }
        let incomingBytes = try Data(contentsOf: source)
        let incoming = try RecordExchange.decode(incomingBytes)
        let localBytes = fm.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil
        let local = try localBytes.map { try RecordExchange.decode($0) }
        var merged = local ?? incoming
        merged.purgedIDs = (local?.purgedIDs ?? []).union(incoming.purgedIDs ?? [])
        merged.sessions = RecordExchange.merge(local: local?.sessions ?? [], incoming: incoming.sessions, purgedIDs: merged.purgedIDs ?? [])
        let backup = destination.appendingPathComponent("backups/storage-migration-\(UUID().uuidString)")
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        try incomingBytes.write(to: backup.appendingPathComponent("project-original.json"), options: .atomic)
        if let localBytes { try localBytes.write(to: backup.appendingPathComponent("local-original.json"), options: .atomic) }
        try RecordExchange.encode(merged).write(to: target, options: .atomic)
        // A retry after interruption is safe: record merging is idempotent.
        try JSONEncoder().encode(source.path).write(to: marker, options: .atomic)
    }
    static func csv(_ sessions: [StudySession]) -> String {
        let iso = ISO8601DateFormatter()
        func field(_ value: String) -> String {
            // Prevent spreadsheet formula execution for user-entered text.
            let dangerous = ["=", "+", "-", "@", "\t", "\r", "\n"]
            let safe = dangerous.contains(where: { value.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = sessions.filter { $0.deletedAt == nil }.map { s in
            [s.id.uuidString, iso.string(from: s.startedAt), iso.string(from: s.endedAt),
             String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), s.activeSeconds),
             s.subject, s.focus].map(field).joined(separator: ",")
        }
        return "\u{FEFF}id,started_at,ended_at,active_seconds,subject,focus\r\n" + rows.joined(separator: "\r\n") + "\r\n"
    }
}
