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
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写活动名称。" }
        if !["S", "A", "B", "C", "D"].contains(focus) { return "请选择有效专注度。" }
        if endedAt < startedAt { return "结束时间不能早于开始时间。" }
        if !activeSeconds.isFinite || activeSeconds < 0 || activeSeconds > endedAt.timeIntervalSince(startedAt) + 0.001 { return "有效时长须在 0 与起止时间差之间。" }
        return nil
    }
}

/// Runtime-only elapsed time that continues through system sleep.
public enum StudyClock {
    private static let origin = ContinuousClock.now
    public static var now: Double {
        let elapsed = origin.duration(to: ContinuousClock.now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
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
    public func seconds(now: Double = StudyClock.now) -> Double {
        accumulated + (runningSince.map { max(0, now - $0) } ?? 0)
    }
    public mutating func toggle(date: Date = Date(), now: Double = StudyClock.now) {
        if let since = runningSince {
            accumulated += max(0, now - since)
            runningSince = nil
        } else {
            if startedAt == nil { startedAt = date }
            runningSince = now
        }
    }
    public mutating func pause(now: Double = StudyClock.now) {
        if isRunning { toggle(now: now) }
    }
    public func checkpoint(now: Double = StudyClock.now) -> TimerState {
        var result = self
        result.accumulated = seconds(now: now)
        result.runningSince = nil
        return result
    }
}

public struct Database: Codable {
    public var goal: GoalSnapshot?
    public var version = 5
    public var timerTransfer: TimerTransfer?
    public var timerID: UUID?
    public var activity: String?
    public var events: [TimeEvent]?
    public var purgedIDs: Set<UUID>?
    public var sessions: [StudySession] = []
    public var draft = TimerState()
    public var pendingEnd: Date?
    public init(version: Int = 5, events: [TimeEvent]? = nil, purgedIDs: Set<UUID>? = nil, sessions: [StudySession] = [], draft: TimerState = TimerState(), pendingEnd: Date? = nil, timerTransfer: TimerTransfer? = nil, activity: String? = nil, goal: GoalSnapshot? = nil) {
        self.goal = goal
        self.timerTransfer = timerTransfer; self.activity = activity
        self.events = events; self.purgedIDs = purgedIDs; self.version = version; self.sessions = sessions; self.draft = draft; self.pendingEnd = pendingEnd
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

/// A point-in-time event, with no duration or focus rating.
public struct TimeEvent: Codable, Identifiable, Equatable {
    public var id: UUID
    public var kind: String
    public var occurredAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public init(id: UUID = UUID(), kind: String, occurredAt: Date, updatedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id; self.kind = kind; self.occurredAt = occurredAt
        self.updatedAt = updatedAt ?? occurredAt; self.deletedAt = deletedAt
    }
    public var modified: Date { max(updatedAt, deletedAt ?? .distantPast) }
}

/// Explicit handoff snapshot. Runtime monotonic anchors never cross devices.
public struct TimerTransfer: Codable {
    public var timerID: UUID?
    public var capturedAt: Date
    public var startedAt: Date?
    public var accumulated: Double
    public var isRunning: Bool
    public var pendingEnd: Date?
    public var activity: String?

    public init(capturedAt: Date = Date(), startedAt: Date?, accumulated: Double, isRunning: Bool, pendingEnd: Date?, activity: String?, timerID: UUID? = nil) {
        self.timerID = timerID
        self.capturedAt = capturedAt; self.startedAt = startedAt; self.accumulated = accumulated
        self.isRunning = isRunning; self.pendingEnd = pendingEnd; self.activity = activity
    }
    public var status: String {
        startedAt == nil ? "未开始" : pendingEnd != nil ? "待保存" : isRunning ? "运行中" : "已暂停"
    }
    public var isValid: Bool {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite, accumulated.isFinite, accumulated >= 0 else { return false }
        guard let start = startedAt else { return accumulated == 0 && !isRunning && pendingEnd == nil }
        guard start.timeIntervalSinceReferenceDate.isFinite, start <= capturedAt else { return false }
        if let end = pendingEnd {
            guard end.timeIntervalSinceReferenceDate.isFinite, end >= start, end <= capturedAt, !isRunning else { return false }
        }
        return accumulated <= (pendingEnd ?? capturedAt).timeIntervalSince(start) + 1
    }
    public func seconds(at date: Date) -> Double {
        accumulated + (isRunning ? max(0, date.timeIntervalSince(capturedAt)) : 0)
    }
    public func mobileClock(at date: Date = Date()) -> MobileClock {
        var clock = MobileClock()
        clock.startedAt = startedAt; clock.accumulated = seconds(at: date)
        clock.runningSince = isRunning ? date : nil; clock.pendingEnd = pendingEnd
        return clock
    }
    public func timerState(at date: Date = Date(), now: Double = StudyClock.now) -> TimerState {
        var timer = TimerState(startedAt: startedAt, accumulated: seconds(at: date))
        timer.runningSince = isRunning ? now : nil
        return timer
    }
}
