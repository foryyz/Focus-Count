import Foundation

public enum FocusMode: String, Codable, CaseIterable {
    case standard, microBreak, course
}

public struct FocusRoutineSettings: Codable, Equatable {
    public var mode: FocusMode = .standard
    public var minimumMinutes = 3
    public var maximumMinutes = 5
    public var microSeconds = 10
    public var roundMinutes = 90
    public var restMinutes = 20
    public var standardVolume = 0.4
    public var microBreakVolume = 0.4
    public var courseVolume = 0.4
    /// Playback uses the settings' mode; editors must use their selected editing mode.
    public var volume: Double {
        get { volume(for: mode) }
        set { setVolume(newValue, for: mode) }
    }
    public func volume(for mode: FocusMode) -> Double {
        switch mode {
        case .standard: return standardVolume
        case .microBreak: return microBreakVolume
        case .course: return courseVolume
        }
    }
    public mutating func setVolume(_ value: Double, for mode: FocusMode) {
        switch mode {
        case .standard: standardVolume = value
        case .microBreak: microBreakVolume = value
        case .course: courseVolume = value
        }
    }
    public func restoringDefaults(for mode: FocusMode) -> Self {
        var next = self
        let defaults = Self()
        next.setVolume(defaults.volume(for: mode), for: mode)
        switch mode {
        case .standard: next.startSound = nil; next.pauseSound = nil
        case .course:
            next.lessonMinutes = defaults.lessonMinutes; next.classBreakMinutes = defaults.classBreakMinutes
            next.classStartSound = nil; next.classEndSound = nil
        case .microBreak:
            next.minimumMinutes = defaults.minimumMinutes; next.maximumMinutes = defaults.maximumMinutes
            next.microSeconds = defaults.microSeconds; next.roundMinutes = defaults.roundMinutes; next.restMinutes = defaults.restMinutes
            next.restSound = nil; next.focusSound = nil
        }
        return next
    }
    public var restSound: String?
    public var focusSound: String?
    public var lessonMinutes = 60
    public var classBreakMinutes = 10
    public var classStartSound: String?
    public var classEndSound: String?
    public var startSound: String?
    public var pauseSound: String?
    public var soundIDs: [String] { [restSound, focusSound, classStartSound, classEndSound, startSound, pauseSound].compactMap { $0 } }
    public var activeFocusSound: String { mode == .course ? (classStartSound ?? "Pop") : (focusSound ?? "Pop") }
    public var activeRestSound: String { mode == .course ? (classEndSound ?? "Glass") : (restSound ?? "Glass") }
    public var focusMinutes: Int { mode == .course ? lessonMinutes : roundMinutes }
    public var breakMinutes: Int { mode == .course ? classBreakMinutes : restMinutes }
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case mode, minimumMinutes, maximumMinutes, microSeconds, roundMinutes, restMinutes, volume, restSound, focusSound
        case lessonMinutes, classBreakMinutes, classStartSound, classEndSound, startSound, pauseSound
        case standardVolume, microBreakVolume, courseVolume
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(FocusMode.self, forKey: .mode)
        minimumMinutes = try values.decode(Int.self, forKey: .minimumMinutes)
        maximumMinutes = try values.decode(Int.self, forKey: .maximumMinutes)
        microSeconds = try values.decode(Int.self, forKey: .microSeconds)
        roundMinutes = try values.decode(Int.self, forKey: .roundMinutes)
        restMinutes = try values.decode(Int.self, forKey: .restMinutes)
        let legacyVolume = try values.decode(Double.self, forKey: .volume)
        standardVolume = try values.decodeIfPresent(Double.self, forKey: .standardVolume) ?? legacyVolume
        microBreakVolume = try values.decodeIfPresent(Double.self, forKey: .microBreakVolume) ?? legacyVolume
        courseVolume = try values.decodeIfPresent(Double.self, forKey: .courseVolume) ?? legacyVolume
        restSound = try values.decodeIfPresent(String.self, forKey: .restSound)
        focusSound = try values.decodeIfPresent(String.self, forKey: .focusSound)
        lessonMinutes = try values.decodeIfPresent(Int.self, forKey: .lessonMinutes) ?? 60
        classBreakMinutes = try values.decodeIfPresent(Int.self, forKey: .classBreakMinutes) ?? 10
        classStartSound = try values.decodeIfPresent(String.self, forKey: .classStartSound)
        classEndSound = try values.decodeIfPresent(String.self, forKey: .classEndSound)
        startSound = try values.decodeIfPresent(String.self, forKey: .startSound)
        pauseSound = try values.decodeIfPresent(String.self, forKey: .pauseSound)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(microBreakVolume, forKey: .volume)
        try values.encode(mode, forKey: .mode)
        try values.encode(minimumMinutes, forKey: .minimumMinutes)
        try values.encode(maximumMinutes, forKey: .maximumMinutes)
        try values.encode(microSeconds, forKey: .microSeconds)
        try values.encode(roundMinutes, forKey: .roundMinutes)
        try values.encode(restMinutes, forKey: .restMinutes)
        try values.encode(standardVolume, forKey: .standardVolume)
        try values.encode(microBreakVolume, forKey: .microBreakVolume)
        try values.encode(courseVolume, forKey: .courseVolume)
        try values.encode(lessonMinutes, forKey: .lessonMinutes)
        try values.encode(classBreakMinutes, forKey: .classBreakMinutes)
        try values.encodeIfPresent(restSound, forKey: .restSound)
        try values.encodeIfPresent(focusSound, forKey: .focusSound)
        try values.encodeIfPresent(classStartSound, forKey: .classStartSound)
        try values.encodeIfPresent(classEndSound, forKey: .classEndSound)
        try values.encodeIfPresent(startSound, forKey: .startSound)
        try values.encodeIfPresent(pauseSound, forKey: .pauseSound)
    }
    public func removingSound(_ id: String) -> Self {
        var next = self
        if next.restSound == id { next.restSound = nil }
        if next.focusSound == id { next.focusSound = nil }
        if next.classStartSound == id { next.classStartSound = nil }
        if next.classEndSound == id { next.classEndSound = nil }
        if next.startSound == id { next.startSound = nil }
        if next.pauseSound == id { next.pauseSound = nil }
        return next
    }
    public var isValid: Bool {
        (1...180).contains(minimumMinutes) && (minimumMinutes...180).contains(maximumMinutes) &&
        (1...300).contains(microSeconds) && (1...360).contains(roundMinutes) &&
        (1...180).contains(restMinutes) && (1...360).contains(lessonMinutes) && (1...180).contains(classBreakMinutes) && [standardVolume, microBreakVolume, courseVolume].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

/// All durations are remaining active wall time. Suspension freezes every phase.
/// Course lessons alternate with class breaks indefinitely; micro-break rounds stop at ready.
public struct FocusRoutine: Codable, Equatable {
    public enum Phase: String, Codable { case focus, microRest, longRest, ready }
    public var settings: FocusRoutineSettings
    public var phase: Phase = .focus
    public var suspended = false
    public var remaining: Double
    public var roundRemaining: Double
    public init(settings: FocusRoutineSettings, random: Double = Double.random(in: 0...1)) {
        self.settings = settings
        roundRemaining = Double(settings.focusMinutes * 60)
        remaining = settings.mode == .course ? roundRemaining : Self.interval(settings, random)
    }
    private static func interval(_ settings: FocusRoutineSettings, _ random: Double) -> Double {
        Double(settings.minimumMinutes * 60) + Double((settings.maximumMinutes - settings.minimumMinutes) * 60) * min(1, max(0, random))
    }
    public var isValid: Bool {
        (settings.mode != .course || ((phase == .focus || phase == .longRest) && remaining > 0 &&
            remaining <= Double((phase == .focus ? settings.lessonMinutes : settings.classBreakMinutes) * 60) &&
            roundRemaining == (phase == .focus ? remaining : 0))) &&
        settings.isValid && remaining.isFinite && roundRemaining.isFinite && remaining >= 0 && roundRemaining >= 0 &&
        roundRemaining <= Double(settings.focusMinutes * 60) && remaining <= Double(max(settings.focusMinutes * 60, max(settings.maximumMinutes * 60, max(settings.microSeconds, settings.breakMinutes * 60))))
    }
    /// Returns only actual focus time; no micro-break or long-break time is counted.
    @discardableResult public mutating func advance(_ seconds: Double, random: () -> Double = { Double.random(in: 0...1) }) -> Double {
        guard !suspended, phase != .ready, seconds.isFinite, seconds > 0 else { return 0 }
        if settings.mode == .course { return advanceCourse(seconds) }
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
    private mutating func advanceCourse(_ seconds: Double) -> Double {
        let lesson = Double(settings.lessonMinutes * 60), rest = Double(settings.classBreakMinutes * 60)
        // Count complete cycles arithmetically, including long background intervals.
        let offset = phase == .focus ? lesson - remaining : lesson + rest - remaining
        let end = offset + seconds, cycle = lesson + rest
        func focusedThrough(_ time: Double) -> Double {
            floor(time / cycle) * lesson + min(lesson, time.truncatingRemainder(dividingBy: cycle))
        }
        let focused = focusedThrough(end) - focusedThrough(offset)
        let position = end.truncatingRemainder(dividingBy: cycle)
        phase = position < lesson ? .focus : .longRest
        remaining = position < lesson ? lesson - position : cycle - position
        roundRemaining = phase == .focus ? remaining : 0
        return focused
    }
    public mutating func nextRound(random: Double = Double.random(in: 0...1)) {
        self = FocusRoutine(settings: settings, random: random)
    }
    public mutating func skipRest(random: Double = Double.random(in: 0...1)) {
        if phase == .microRest { phase = .focus; remaining = Self.interval(settings, random) }
        else if phase == .longRest || phase == .ready {
            let wasSuspended = suspended
            nextRound(random: random)
            suspended = wasSuspended
        }
    }
}
