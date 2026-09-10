import Foundation
import CryptoKit

public struct StudySession: Codable, Identifiable {
    public var id = UUID()
    public var startedAt: Date
    public var endedAt: Date
    public var activeSeconds: Double
    public var subject: String
    public var focus: String
    public var updatedAt: Date?
    public var deletedAt: Date?
    public var history: [SessionSnapshot]?

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, activeSeconds: Double, subject: String, focus: String, updatedAt: Date? = nil, deletedAt: Date? = nil, history: [SessionSnapshot]? = nil) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt
        self.activeSeconds = activeSeconds; self.subject = subject; self.focus = focus
        self.updatedAt = updatedAt; self.deletedAt = deletedAt; self.history = history
    }

    public var validationError: String? {
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写学习科目。" }
        if !["S", "A", "B", "C", "D"].contains(focus) { return "请选择有效专注度。" }
        if endedAt < startedAt { return "结束时间不能早于开始时间。" }
        if !activeSeconds.isFinite || activeSeconds < 0 || activeSeconds > endedAt.timeIntervalSince(startedAt) + 0.001 { return "有效时长须在 0 与起止时间差之间。" }
        return nil
    }
}

public struct TimerState: Codable {
    public var startedAt: Date?
    public var accumulated: Double = 0
    // Monotonic timestamps are runtime-only: restored timers always start paused.
    public var runningSince: Double?
    enum CodingKeys: String, CodingKey { case startedAt, accumulated }
    public init(startedAt: Date? = nil, accumulated: Double = 0) { self.startedAt = startedAt; self.accumulated = accumulated }
    public var isRunning: Bool { runningSince != nil }
    public func seconds(now: Double = ProcessInfo.processInfo.systemUptime) -> Double {
        accumulated + (runningSince.map { max(0, now - $0) } ?? 0)
    }
    public mutating func toggle(date: Date = Date(), now: Double = ProcessInfo.processInfo.systemUptime) {
        if let since = runningSince {
            accumulated += max(0, now - since)
            runningSince = nil
        } else {
            if startedAt == nil { startedAt = date }
            runningSince = now
        }
    }
    public mutating func pause(now: Double = ProcessInfo.processInfo.systemUptime) {
        if isRunning { toggle(now: now) }
    }
    public func checkpoint(now: Double = ProcessInfo.processInfo.systemUptime) -> TimerState {
        var result = self
        result.accumulated = seconds(now: now)
        result.runningSince = nil
        return result
    }
}

public struct Database: Codable {
    public var version = 4
    public var purgedIDs: Set<UUID>?
    public var sessions: [StudySession] = []
    public var draft = TimerState()
    public var pendingEnd: Date?
    public init(version: Int = 4, purgedIDs: Set<UUID>? = nil, sessions: [StudySession] = [], draft: TimerState = TimerState(), pendingEnd: Date? = nil) {
        self.purgedIDs = purgedIDs; self.version = version; self.sessions = sessions; self.draft = draft; self.pendingEnd = pendingEnd
    }
}

/// Flat, portable prior version; never counted as a separate study session.
public struct SessionSnapshot: Codable, Hashable, Identifiable {
    public var sessionID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var activeSeconds: Double
    public var subject: String
    public var focus: String
    public var updatedAt: Date?
    public var deletedAt: Date?
    public init(_ value: StudySession) {
        sessionID = value.id; startedAt = value.startedAt; endedAt = value.endedAt
        activeSeconds = value.activeSeconds; subject = value.subject; focus = value.focus
        updatedAt = value.updatedAt ?? value.endedAt; deletedAt = value.deletedAt
    }
    public var session: StudySession {
        StudySession(id: sessionID, startedAt: startedAt, endedAt: endedAt, activeSeconds: activeSeconds,
                     subject: subject, focus: focus, updatedAt: updatedAt, deletedAt: deletedAt)
    }
    public var id: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // All imported versions are validated before use; dates and seconds must be finite.
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}
