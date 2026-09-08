import Foundation

struct StudySession: Codable, Identifiable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date
    var activeSeconds: Double
    var subject: String
    var focus: String
    var updatedAt: Date?
    var deletedAt: Date?

    var validationError: String? {
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写学习科目。" }
        if !["S", "A", "B", "C", "D"].contains(focus) { return "请选择有效专注度。" }
        if endedAt < startedAt { return "结束时间不能早于开始时间。" }
        if !activeSeconds.isFinite || activeSeconds < 0 || activeSeconds > endedAt.timeIntervalSince(startedAt) + 0.001 { return "有效时长须在 0 与起止时间差之间。" }
        return nil
    }
}

struct TimerState: Codable {
    var startedAt: Date?
    var accumulated: Double = 0
    // Monotonic timestamps are runtime-only: restored timers always start paused.
    var runningSince: Double?
    enum CodingKeys: String, CodingKey { case startedAt, accumulated }
    var isRunning: Bool { runningSince != nil }
    func seconds(now: Double = ProcessInfo.processInfo.systemUptime) -> Double {
        accumulated + (runningSince.map { max(0, now - $0) } ?? 0)
    }
    mutating func toggle(date: Date = Date(), now: Double = ProcessInfo.processInfo.systemUptime) {
        if let since = runningSince {
            accumulated += max(0, now - since)
            runningSince = nil
        } else {
            if startedAt == nil { startedAt = date }
            runningSince = now
        }
    }
    mutating func pause(now: Double = ProcessInfo.processInfo.systemUptime) {
        if isRunning { toggle(now: now) }
    }
    func checkpoint(now: Double = ProcessInfo.processInfo.systemUptime) -> TimerState {
        var result = self
        result.accumulated = seconds(now: now)
        result.runningSince = nil
        return result
    }
}

struct Database: Codable {
    var version = 2
    var sessions: [StudySession] = []
    var draft = TimerState()
    var pendingEnd: Date?
}

enum Storage {
    // Resolve from the executable, never the shell's working directory.
    // Both dist/macos/FocusCount.app and SwiftPM's .build live below the root.
    static func projectDirectory(executable: URL) throws -> URL {
        var candidate = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        while true {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".focuscount-root").path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
        throw NSError(domain: "FocusCount.Storage", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "找不到项目根目录，请将应用放在项目的 dist/macos 目录中，并保留 .focuscount-root 文件。"])
    }
    static var directory: URL {
        get throws {
            guard let executable = Bundle.main.executableURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try projectDirectory(executable: executable).appendingPathComponent("data", isDirectory: true)
        }
    }
    static var legacyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusCount", isDirectory: true)
    }
    // Copy only when no shared database exists. Keep the original as a backup.
    static func migrateLegacyData(from legacy: URL, to destination: URL) throws {
        let target = destination.appendingPathComponent("sessions.json")
        let source = legacy.appendingPathComponent("sessions.json")
        guard !FileManager.default.fileExists(atPath: target.path),
              FileManager.default.fileExists(atPath: source.path) else { return }
        let contents = try Data(contentsOf: source)
        let database = try JSONDecoder().decode(Database.self, from: contents)
        guard [1, 2].contains(database.version) else { throw CocoaError(.fileReadUnknown) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try contents.write(to: target, options: .atomic)
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
