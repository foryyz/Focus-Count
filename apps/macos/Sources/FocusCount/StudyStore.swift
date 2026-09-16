import FocusCountCore
import SwiftUI
import AppKit

@MainActor final class StudyStore: ObservableObject {
    @Published var database = Database()
    @Published var error: String?
    @Published var blocked = false
    private var ticker: Timer?
    private var ticks = 0
    private var observers: [NSObjectProtocol] = []
    private var file: URL { get throws { try self.directory.appendingPathComponent("sessions.json") } }

    private let customDirectory: URL?
    private var directory: URL { get throws { try customDirectory ?? Storage.directory } }
    var sessions: [StudySession] { database.sessions.filter { $0.deletedAt == nil } }
    var subjects: [String] { Array(Set(sessions.map(\.subject))).sorted() }

    init(directory: URL? = nil, observeSystem: Bool = true) {
        customDirectory = directory
        do {
            if customDirectory == nil, let executable = Bundle.main.executableURL {
                try Storage.migrateProjectData(executable: executable, to: self.directory)
            }
            if try FileManager.default.fileExists(atPath: file.path) {
                let contents = try Data(contentsOf: file)
                database = try JSONDecoder().decode(Database.self, from: contents)
                guard [1, 2, 3, 4, 5].contains(database.version) else { throw CocoaError(.fileReadUnknown) }
                let validated = try RecordExchange.decode(contents)
                database.sessions = validated.sessions
                database.events = validated.events
                if database.version < 5 {
                    let backup = try self.directory.appendingPathComponent("sessions.v\(database.version).backup.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try contents.write(to: backup, options: .atomic) }
                    database.version = 5
                    for index in database.sessions.indices {
                        database.sessions[index].updatedAt = database.sessions[index].updatedAt ?? database.sessions[index].endedAt
                    }
                }
            }
        } catch {
            blocked = true
            self.error = "无法读取数据，已停止写入以保护原文件。请检查数据目录：\(error.localizedDescription)"
        }
        if !blocked {
            do { try writeCSV() } catch { self.error = "CSV 更新失败：\(error.localizedDescription)" }
        }
        guard observeSystem else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.objectWillChange.send()
                self.ticks += 1
                if self.ticks % 20 == 0 && self.database.draft.isRunning { self.persist() }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForSleep() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAfterWake() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.persist() }
        })
    }
    @discardableResult func persist() -> Bool {
        guard !blocked else { return false }
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            var snapshot = database
            snapshot.draft = database.draft.checkpoint()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: file, options: .atomic)
            return true
        } catch { self.error = "保存失败：\(error.localizedDescription)"; return false }
    }
    func writeCSV() throws {
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try Data(Storage.csv(database.sessions).utf8).write(to: self.directory.appendingPathComponent("sessions.csv"), options: .atomic)
    }
    @discardableResult func markEvent(kind: String = "SEX", at date: Date = Date()) -> Bool {
        commit {
            if $0.events == nil { $0.events = [] }
            $0.events?.append(TimeEvent(kind: kind, occurredAt: date))
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
    func prepareForSleep() { _ = persist() }
    func refreshAfterWake() {
        objectWillChange.send()
        _ = persist()
    }
    @discardableResult func cancelTimer() -> Bool {
        commit {
            $0.draft = TimerState()
            $0.pendingEnd = nil
        }
    }
    func toggle() {
        guard !blocked, database.pendingEnd == nil else { return }
        database.draft.toggle()
        persist()
    }
    func pause() { database.draft.pause(); persist() }
    func finish() {
        guard !blocked, database.draft.startedAt != nil else { return }
        database.draft.pause()
        database.pendingEnd = Date()
        persist()
    }
    func resumeEditingTimer() { database.pendingEnd = nil; persist() }
    func save(subject: String, focus: String) -> Bool {
        guard !blocked, let start = database.draft.startedAt, let end = database.pendingEnd else { return false }
        let session = StudySession(startedAt: start, endedAt: end, activeSeconds: database.draft.seconds(), subject: subject.trimmingCharacters(in: .whitespacesAndNewlines), focus: focus, updatedAt: Date())
        return commit { database in
            database.sessions.append(session)
            database.draft = TimerState()
            database.pendingEnd = nil
        }
    }
    private func commit(_ change: (inout Database) -> Void) -> Bool {
        guard !blocked else { return false }
        let old = database
        change(&database)
        error = nil
        guard persist() else { database = old; return false }
        do { try writeCSV() } catch { self.error = "记录已保存，但 CSV 更新失败：\(error.localizedDescription)" }
        return true
    }
    func upsert(_ session: StudySession) -> Bool {
        guard !(database.purgedIDs ?? []).contains(session.id) else { error = "此记录已彻底删除。"; return false }
        var edited = session
        edited.subject = edited.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = edited.validationError { error = problem; return false }
        edited.updatedAt = Date()
        return commit { database in
            if let index = database.sessions.firstIndex(where: { $0.id == edited.id }) {
                database.sessions[index] = RecordExchange.replacing(database.sessions[index], with: edited)
            } else { database.sessions.append(edited) }
        }
    }
    @discardableResult func setDeleted(_ id: UUID, deleted: Bool) -> Bool {
        guard let index = database.sessions.firstIndex(where: { $0.id == id }) else { return false }
        return commit { database in
            var changed = database.sessions[index]
            changed.deletedAt = deleted ? Date() : nil
            database.sessions[index] = RecordExchange.replacing(database.sessions[index], with: changed)
        }
    }
    @discardableResult func permanentlyDelete(_ ids: Set<UUID>) -> Bool {
        return commit {
            let removed = Set($0.sessions.filter { ids.contains($0.id) && $0.deletedAt != nil }.map(\.id))
            $0.purgedIDs = ($0.purgedIDs ?? []).union(removed)
            $0.sessions.removeAll { removed.contains($0.id) }
        }
    }
    func importRecords(_ incoming: Database) -> Bool {
        guard !blocked else { return false }
        do {
            let validated = try RecordExchange.decode(RecordExchange.encode(incoming))
            let backupFolder = try directory.appendingPathComponent("backups/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
            try export().write(to: backupFolder.appendingPathComponent("before-import.json"), options: .atomic)
            try RecordExchange.encode(incoming).write(to: backupFolder.appendingPathComponent("incoming.json"), options: .atomic)
            return commit {
                $0.purgedIDs = ($0.purgedIDs ?? []).union(validated.purgedIDs ?? [])
                $0.sessions = RecordExchange.merge(local: $0.sessions, incoming: validated.sessions, purgedIDs: $0.purgedIDs ?? [])
                $0.events = RecordExchange.mergeEvents(local: $0.events ?? [], incoming: validated.events ?? [], purgedIDs: $0.purgedIDs ?? [])
            }
        } catch { self.error = "导入失败，原数据未修改：\(error.localizedDescription)"; return false }
    }
    func export() throws -> Data {
        guard !blocked else { throw RecordExchange.ExchangeError.invalid("数据读取失败，无法导出。") }
        var snapshot = database
        snapshot.draft = database.draft.checkpoint()
        return try RecordExchange.encode(snapshot)
    }
    func restoreVersion(_ snapshot: SessionSnapshot) -> Bool {
        guard let current = database.sessions.first(where: { $0.id == snapshot.sessionID }) else { return false }
        // Restore as a new edit, retaining both the current and all archived versions.
        return commit { database in
            if let index = database.sessions.firstIndex(where: { $0.id == current.id }) {
                database.sessions[index] = RecordExchange.replacing(current, with: snapshot.session)
            }
        }
    }
}

enum FocusCommand: Equatable {
    case toggle, stop, sex, unknown
    init(_ input: String) {
        switch input.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "": self = .toggle
        case "!stop": self = .stop
        case "!sex": self = .sex
        default: self = .unknown
        }
    }
}
