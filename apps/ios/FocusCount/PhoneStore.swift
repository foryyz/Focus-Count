import SwiftUI
import FocusCountCore

struct PhoneState: Codable {
    var version = 1
    var sessions: [StudySession] = []
    var clock = MobileClock()
}

@MainActor final class PhoneStore: ObservableObject {
    @Published private(set) var state = PhoneState()
    @Published var error: String?
    @Published private(set) var blocked = false
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("app-state.json") }
    var sessions: [StudySession] { state.sessions.filter { $0.deletedAt == nil } }
    var subjects: [String] { Array(Set(sessions.map(\.subject))).sorted() }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FocusCount", isDirectory: true)
        if directory == nil {
            // Make an offline export destination visible in the Files app.
            let exports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
            try? FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        }
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                let loaded = try JSONDecoder().decode(PhoneState.self, from: data)
                guard loaded.version == 1, loaded.clock.isValid else { throw CocoaError(.fileReadCorruptFile) }
                // Validate the records with the same rules as interchange files.
                _ = try RecordExchange.decode(RecordExchange.encode(Database(sessions: loaded.sessions)))
                state = loaded
            }
        } catch { blocked = true; self.error = "无法读取本地数据，已停止写入保护原文件。\n\(error.localizedDescription)" }
    }
    @discardableResult private func commit(_ change: (inout PhoneState) -> Void) -> Bool {
        guard !blocked else { return false }
        var next = state; change(&next)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: file, options: .atomic)
            state = next; error = nil
            return true
        } catch { self.error = "保存失败，修改未生效：\(error.localizedDescription)"; return false }
    }
    func toggle() { commit { $0.clock.toggle() } }
    func finish() { commit { $0.clock.finish() } }
    func returnToTimer() { commit { $0.clock.pendingEnd = nil } }
    func checkpoint() { commit { _ in } }
    func save(_ session: StudySession, completesTimer: Bool = false) -> Bool {
        var edited = session
        edited.subject = edited.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = edited.validationError { error = issue; return false }
        edited.updatedAt = Date()
        return commit {
            if let index = $0.sessions.firstIndex(where: { $0.id == edited.id }) { $0.sessions[index] = edited }
            else { $0.sessions.append(edited) }
            if completesTimer { $0.clock = MobileClock() }
        }
    }
    func delete(_ session: StudySession, restore: Bool = false) {
        commit {
            guard let index = $0.sessions.firstIndex(where: { $0.id == session.id }) else { return }
            $0.sessions[index].deletedAt = restore ? nil : Date()
            $0.sessions[index].updatedAt = Date()
        }
    }
    func importRecords(_ database: Database) -> Bool {
        guard !blocked else { return false }
        do {
            // Preserve a backup before each import, including the current timer.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let backup = directory.appendingPathComponent("before-import-\(UUID().uuidString).json")
            try JSONEncoder().encode(state).write(to: backup, options: .atomic)
        } catch { self.error = "导入前备份失败：\(error.localizedDescription)"; return false }
        return commit { $0.sessions = RecordExchange.merge(local: $0.sessions, incoming: database.sessions) }
    }
    func export() throws -> Data {
        guard !blocked else { throw RecordExchange.ExchangeError.invalid("本地数据读取失败，无法导出。") }
        let draft = TimerState(startedAt: state.clock.startedAt, accumulated: state.clock.seconds())
        return try RecordExchange.encode(Database(sessions: state.sessions, draft: draft, pendingEnd: state.clock.pendingEnd))
    }
}

func phoneDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "--:--:--" }
    let value = Int(seconds)
    return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
}
