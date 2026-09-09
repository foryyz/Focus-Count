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
        guard [1, 2].contains(database.version) else { throw ExchangeError.invalid("不支持此数据版本。") }
        var ids = Set<UUID>()
        for index in database.sessions.indices {
            let session = database.sessions[index]
            guard ids.insert(session.id).inserted else { throw ExchangeError.invalid("文件包含重复的记录 ID。") }
            if let issue = session.validationError { throw ExchangeError.invalid("记录“\(session.subject)”无效：\(issue)") }
            database.sessions[index].updatedAt = session.updatedAt ?? session.endedAt
        }
        database.version = 2
        return database
    }
    /// Ties keep local data. A tombstone is a record and follows the same merge rule.
    public static func merge(local: [StudySession], incoming: [StudySession]) -> [StudySession] {
        var result = local
        var positions = Dictionary(uniqueKeysWithValues: local.enumerated().map { ($0.element.id, $0.offset) })
        for session in incoming {
            if let index = positions[session.id] {
                if modified(session) > modified(result[index]) { result[index] = session }
            } else {
                positions[session.id] = result.count; result.append(session)
            }
        }
        return result
    }
    public static func modified(_ session: StudySession) -> Date {
        max(session.updatedAt ?? session.endedAt, session.deletedAt ?? .distantPast)
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
