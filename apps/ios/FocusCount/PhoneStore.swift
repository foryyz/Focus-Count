import SwiftUI
import FocusCountCore

struct PhoneState: Codable {
    var version = 5
    var events: [TimeEvent]?
    var purgedIDs: Set<UUID>?
    var sessions: [StudySession] = []
    var clock = MobileClock()
    var activity: String?
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
                var loaded = try JSONDecoder().decode(PhoneState.self, from: data)
                guard [1, 2, 3, 4, 5].contains(loaded.version), loaded.clock.isValid else { throw CocoaError(.fileReadCorruptFile) }
                // Validate the records with the same rules as interchange files.
                let validated = try RecordExchange.decode(RecordExchange.encode(Database(events: loaded.events, purgedIDs: loaded.purgedIDs, sessions: loaded.sessions)))
                loaded.sessions = validated.sessions
                loaded.events = validated.events
                if loaded.version < 5 {
                    let backup = self.directory.appendingPathComponent("app-state.v\(loaded.version).backup.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) }
                    loaded.version = 5
                }
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
    @discardableResult func cancelTimer() -> Bool { commit { $0.clock = MobileClock(); $0.activity = nil } }
    @discardableResult func start(activity: String) -> Bool {
        guard state.clock.startedAt == nil else { return false }
        return commit {
            $0.activity = activity.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.clock.toggle()
        }
    }
    @discardableResult func markCommand(_ command: String, at date: Date = Date()) -> Bool {
        let input = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.hasPrefix("!") else { error = "输入 ! 加标记文字，例如 !sad。"; return false }
        return markEvent(kind: String(input.dropFirst()), at: date)
    }
    @discardableResult func markEvent(kind: String = "sex", at date: Date = Date()) -> Bool {
        let label = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !label.isEmpty else { error = "请在 ! 后填写标记文字。"; return false }
        return commit {
            if $0.events == nil { $0.events = [] }
            $0.events?.append(TimeEvent(kind: label, occurredAt: date))
        }
    }
    @discardableResult func setEventDeleted(_ id: UUID, deleted: Bool) -> Bool {
        commit {
            guard let index = $0.events?.firstIndex(where: { $0.id == id }) else { return }
            let now = max(Date(), $0.events![index].modified.addingTimeInterval(0.001))
            $0.events![index].deletedAt = deleted ? now : nil
            $0.events![index].updatedAt = now
        }
    }
    @discardableResult func purgeEvents(_ ids: Set<UUID>) -> Bool {
        commit {
            let removed = Set(($0.events ?? []).filter { ids.contains($0.id) && $0.deletedAt != nil }.map(\.id))
            $0.purgedIDs = ($0.purgedIDs ?? []).union(removed)
            $0.events?.removeAll { removed.contains($0.id) }
        }
    }
    func toggle() { commit { $0.clock.toggle() } }
    func finish() { commit { $0.clock.finish() } }
    func returnToTimer() { commit { $0.clock.pendingEnd = nil } }
    func checkpoint() { commit { _ in } }
    func save(_ session: StudySession, completesTimer: Bool = false) -> Bool {
        guard !(state.purgedIDs ?? []).contains(session.id) else { error = "此记录已彻底删除。"; return false }
        var edited = session
        edited.subject = edited.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = edited.validationError { error = issue; return false }
        edited.updatedAt = Date()
        return commit {
            if let index = $0.sessions.firstIndex(where: { $0.id == edited.id }) { $0.sessions[index] = RecordExchange.replacing($0.sessions[index], with: edited) }
            else { $0.sessions.append(edited) }
            if completesTimer { $0.clock = MobileClock(); $0.activity = nil }
        }
    }
    func delete(_ session: StudySession, restore: Bool = false) {
        commit {
            guard let index = $0.sessions.firstIndex(where: { $0.id == session.id }) else { return }
            var changed = $0.sessions[index]
            changed.deletedAt = restore ? nil : Date()
            $0.sessions[index] = RecordExchange.replacing($0.sessions[index], with: changed)
        }
    }
    @discardableResult func permanentlyDelete(_ ids: Set<UUID>) -> Bool {
        return commit {
            let removed = Set($0.sessions.filter { ids.contains($0.id) && $0.deletedAt != nil }.map(\.id))
            $0.purgedIDs = ($0.purgedIDs ?? []).union(removed)
            $0.sessions.removeAll { removed.contains($0.id) }
        }
    }
    func importRecords(_ database: Database) -> Bool {
        guard !blocked else { return false }
        do {
            let incoming = try RecordExchange.decode(RecordExchange.encode(database))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let identifier = UUID().uuidString
            try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("before-import-\(identifier).json"), options: .atomic)
            try RecordExchange.encode(database).write(to: directory.appendingPathComponent("incoming-\(identifier).json"), options: .atomic)
            return commit {
                $0.purgedIDs = ($0.purgedIDs ?? []).union(incoming.purgedIDs ?? [])
                $0.sessions = RecordExchange.merge(local: $0.sessions, incoming: incoming.sessions, purgedIDs: $0.purgedIDs ?? [])
                $0.events = RecordExchange.mergeEvents(local: $0.events ?? [], incoming: incoming.events ?? [], purgedIDs: $0.purgedIDs ?? [])
            }
        } catch { self.error = "导入失败，原数据未修改：\(error.localizedDescription)"; return false }
    }
    func restoreVersion(_ snapshot: SessionSnapshot) {
        commit {
            guard let index = $0.sessions.firstIndex(where: { $0.id == snapshot.sessionID }) else { return }
            $0.sessions[index] = RecordExchange.replacing($0.sessions[index], with: snapshot.session)
        }
    }
    func export() throws -> Data {
        guard !blocked else { throw RecordExchange.ExchangeError.invalid("本地数据读取失败，无法导出。") }
        let draft = TimerState(startedAt: state.clock.startedAt, accumulated: state.clock.seconds())
        return try RecordExchange.encode(Database(events: state.events, purgedIDs: state.purgedIDs, sessions: state.sessions, draft: draft, pendingEnd: state.clock.pendingEnd))
    }
}

func phoneDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "--:--:--" }
    let value = Int(seconds)
    return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
}

// Coordinate document-provider reads while retaining the selected security scope.
enum PhoneImportFile {
    static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            result = Result {
                let limit = 20_000_000
                let size = try readableURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= limit else { throw RecordExchange.ExchangeError.invalid("文件超过 20 MB。") }
                let data = try Data(contentsOf: readableURL)
                guard data.count <= limit else { throw RecordExchange.ExchangeError.invalid("文件超过 20 MB。") }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw RecordExchange.ExchangeError.invalid("文件暂时无法读取，请在“文件”应用中下载后重试。") }
        return try result.get()
    }
}
