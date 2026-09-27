import Foundation

public enum FocusMode: String, Codable, CaseIterable {
    case standard, microBreak
}

public struct FocusRoutineSettings: Codable, Equatable {
    public var mode: FocusMode = .standard
    public var minimumMinutes = 3
    public var maximumMinutes = 5
    public var microSeconds = 10
    public var roundMinutes = 90
    public var restMinutes = 20
    public var volume = 0.4
    public init() {}
    public var isValid: Bool {
        (1...180).contains(minimumMinutes) && (minimumMinutes...180).contains(maximumMinutes) &&
        (1...300).contains(microSeconds) && (1...360).contains(roundMinutes) &&
        (1...180).contains(restMinutes) && volume.isFinite && (0...1).contains(volume)
    }
}

/// All durations are remaining active wall time. Suspension freezes every phase.
public struct FocusRoutine: Codable, Equatable {
    public enum Phase: String, Codable { case focus, microRest, longRest, ready }
    public var settings: FocusRoutineSettings
    public var phase: Phase = .focus
    public var suspended = false
    public var remaining: Double
    public var roundRemaining: Double
    public init(settings: FocusRoutineSettings, random: Double = Double.random(in: 0...1)) {
        self.settings = settings
        roundRemaining = Double(settings.roundMinutes * 60)
        remaining = Self.interval(settings, random)
    }
    private static func interval(_ settings: FocusRoutineSettings, _ random: Double) -> Double {
        Double(settings.minimumMinutes * 60) + Double((settings.maximumMinutes - settings.minimumMinutes) * 60) * min(1, max(0, random))
    }
    public var isValid: Bool {
        settings.isValid && remaining.isFinite && roundRemaining.isFinite && remaining >= 0 && roundRemaining >= 0 &&
        roundRemaining <= Double(settings.roundMinutes * 60) && remaining <= Double(max(settings.maximumMinutes * 60, max(settings.microSeconds, settings.restMinutes * 60)))
    }
    /// Returns only actual focus time; no micro-break or long-break time is counted.
    @discardableResult public mutating func advance(_ seconds: Double, random: () -> Double = { Double.random(in: 0...1) }) -> Double {
        guard !suspended, phase != .ready, seconds.isFinite, seconds > 0 else { return 0 }
        var elapsed = seconds, focused = 0.0
        while elapsed > 0 && phase != .ready {
            let step = min(elapsed, phase == .longRest ? remaining : min(remaining, roundRemaining))
            if phase == .focus { focused += step }
            elapsed -= step; remaining -= step
            if phase != .longRest { roundRemaining -= step }
            if phase != .longRest && roundRemaining <= 0 {
                phase = .longRest; remaining = Double(settings.restMinutes * 60)
            } else if remaining <= 0 {
                switch phase {
                case .focus: phase = .microRest; remaining = Double(settings.microSeconds)
                case .microRest: phase = .focus; remaining = Self.interval(settings, random())
                case .longRest: phase = .ready; remaining = 0
                case .ready: break
                }
            }
        }
        return focused
    }
    public mutating func nextRound(random: Double = Double.random(in: 0...1)) {
        self = FocusRoutine(settings: settings, random: random)
    }
    public mutating func skipRest(random: Double = Double.random(in: 0...1)) {
        if phase == .microRest { phase = .focus; remaining = Self.interval(settings, random) }
        else if phase == .longRest || phase == .ready { nextRound(random: random) }
    }
}
