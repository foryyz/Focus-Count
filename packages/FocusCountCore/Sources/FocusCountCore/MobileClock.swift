import Foundation

/// Persists a wall-clock anchor so iOS suspension and lock screen do not stop a session.
/// Background execution is not required. Manual system-clock changes affect elapsed time.
public struct MobileClock: Codable {
    public var startedAt: Date?
    public var accumulated: Double = 0
    public var runningSince: Date?
    public var pendingEnd: Date?
    public init() {}
    public var isRunning: Bool { runningSince != nil }
    public func seconds(at date: Date = Date()) -> Double {
        accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
    public mutating func toggle(at date: Date = Date()) {
        guard pendingEnd == nil else { return }
        if runningSince != nil { pause(at: date) }
        else { if startedAt == nil { startedAt = date }; runningSince = date }
    }
    public mutating func pause(at date: Date = Date()) {
        accumulated = seconds(at: date); runningSince = nil
    }
    public mutating func finish(at date: Date = Date()) {
        guard startedAt != nil else { return }
        pause(at: date); pendingEnd = date
    }
    public var isValid: Bool {
        accumulated.isFinite && accumulated >= 0 &&
        (startedAt != nil || (accumulated == 0 && runningSince == nil && pendingEnd == nil)) &&
        !(runningSince != nil && pendingEnd != nil)
    }
}

public enum RecordExchange {
    public static func decode(_ data: Data) throws -> Database {
        var database = try JSONDecoder().decode(Database.self, from: data)
        guard [1, 2, 3, 4, 5].contains(database.version) else { throw ExchangeError.invalid("不支持此数据版本。") }
        if let timer = database.timerTransfer, !timer.isValid {
            throw ExchangeError.invalid("文件中的计时状态无效。")
        }
        var ids = Set<UUID>()
        for index in database.sessions.indices {
            let session = database.sessions[index]
            guard ids.insert(session.id).inserted else { throw ExchangeError.invalid("文件包含重复的记录 ID。") }
            if let issue = session.validationError { throw ExchangeError.invalid("记录“\(session.subject)”无效：\(issue)") }
            for snapshot in session.history ?? [] {
                guard snapshot.sessionID == session.id, snapshot.session.validationError == nil else {
                    throw ExchangeError.invalid("记录历史版本无效。")
                }
            }
            database.sessions[index].updatedAt = session.updatedAt ?? session.endedAt
        }
        database.sessions.removeAll { (database.purgedIDs ?? []).contains($0.id) }
        for event in database.events ?? [] {
            guard ids.insert(event.id).inserted, !event.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ExchangeError.invalid("时间标记无效或 ID 重复。")
            }
        }
        database.events = (database.events ?? []).filter { !(database.purgedIDs ?? []).contains($0.id) }
        database.version = 5
        return database
    }
    /// Merge is commutative and idempotent: every distinct version travels with the record.
    public static func merge(local: [StudySession], incoming: [StudySession], purgedIDs: Set<UUID> = []) -> [StudySession] {
        var records: [UUID: StudySession] = [:]
        for session in local + incoming where !purgedIDs.contains(session.id) {
            if let old = records[session.id] {
                let oldSnapshot = SessionSnapshot(old), newSnapshot = SessionSnapshot(session)
                let winner: StudySession
                if modified(old) == modified(session) {
                    winner = oldSnapshot.id >= newSnapshot.id ? old : session
                } else { winner = modified(old) > modified(session) ? old : session }
                records[session.id] = retainingVersions(winner: winner, sources: [old, session])
            } else { records[session.id] = retainingVersions(winner: session, sources: [session]) }
        }
        return records.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private static func retainingVersions(winner: StudySession, sources: [StudySession]) -> StudySession {
        var result = winner
        result.updatedAt = winner.updatedAt ?? winner.endedAt
        var versions = Set(sources.flatMap { ($0.history ?? []) + [SessionSnapshot($0)] })
        versions.remove(SessionSnapshot(result))
        let ordered = versions.sorted { $0.id < $1.id }
        result.history = ordered.isEmpty ? nil : ordered
        return result
    }
    public static func replacing(_ old: StudySession, with edited: StudySession, now: Date = Date()) -> StudySession {
        var next = edited
        next.updatedAt = max(now, modified(old).addingTimeInterval(0.001))
        return retainingVersions(winner: next, sources: [old])
    }
    public static func archivedCount(_ sessions: [StudySession]) -> Int {
        sessions.reduce(0) { $0 + ($1.history?.count ?? 0) }
    }
    public static func modified(_ session: StudySession) -> Date {
        max(session.updatedAt ?? session.endedAt, session.deletedAt ?? .distantPast)
    }
    public static func mergeEvents(local: [TimeEvent], incoming: [TimeEvent], purgedIDs: Set<UUID> = []) -> [TimeEvent] {
        var result: [UUID: TimeEvent] = [:]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for event in local + incoming where !purgedIDs.contains(event.id) {
            if let old = result[event.id] {
                if event.modified < old.modified { continue }
                if event.modified == old.modified {
                    let left = (try? encoder.encode(old)) ?? Data()
                    let right = (try? encoder.encode(event)) ?? Data()
                    if !left.lexicographicallyPrecedes(right) { continue }
                }
            }
            result[event.id] = event
        }
        return result.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    public static func encode(_ database: Database) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(database)
    }
    public enum ExchangeError: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
    }
}
