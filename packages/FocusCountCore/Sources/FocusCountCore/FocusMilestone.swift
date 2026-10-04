import Foundation

public enum FocusMilestone: Int, CaseIterable {
    case beginning, blue, ice, violet, silver, jewel, roseGold, gold, radiant, finalPush, achieved
    public static let themeKey = "focus-rewards-theme-v1"
    public init(seconds: Double) {
        let hours = seconds.isFinite ? max(0, seconds) / 3600 : 0
        switch hours {
        case ..<1: self = .beginning
        case ..<2: self = .blue
        case ..<3: self = .ice
        case ..<4: self = .violet
        case ..<5: self = .silver
        case ..<6: self = .jewel
        case ..<7: self = .roseGold
        case ..<8: self = .gold
        case ..<9: self = .radiant
        case ..<10: self = .finalPush
        default: self = .achieved
        }
    }
    /// Round upward so the final partial minute never displays zero before achievement.
    public static func remainingAchievementMinutes(seconds: Double) -> Int? {
        guard seconds.isFinite, FocusMilestone(seconds: seconds) == .finalPush else { return nil }
        return Int(ceil((36000 - seconds) / 60))
    }
    public var lightsHome: Bool { rawValue >= Self.roseGold.rawValue }
    public var encouragement: String {
        switch self {
        case .beginning: return "再专注一会儿，点亮今天。"
        case .blue: return "今天已经被你点亮。"
        case .ice: return "一点一滴，正在成为积累。"
        case .violet: return "每一份投入，都在积累力量。"
        case .silver: return "沉下心来，时间会给你答案。"
        case .jewel: return "你的坚持，正在闪闪发光。"
        case .roseGold: return "今天已经很出色了。"
        case .gold: return "今天的努力，值得闪耀。"
        case .radiant: return "每一小时，都让今天更耀眼。"
        case .finalPush: return ""
        case .achieved: return ""
        }
    }
}

public enum FocusCelebration {
    public enum Reason { case automatic, manual, preview }
    /// Preview and manual requests never read or write the daily automatic celebration claim.
    public static func request(seconds: Double, reason: Reason, at date: Date = Date(),
                               calendar: Calendar = .current,
                               storage: any PreferenceStorage = ApplicationPreferences.current) -> Bool {
        guard FocusMilestone(seconds: seconds) == .achieved else { return false }
        if reason != .automatic { return true }
        return claim(seconds: seconds, at: date, calendar: calendar, storage: storage)
    }
    private static let key = "focus-celebration-day-v1"
    public static func day(at date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
    /// Local once-per-day claim, independent of record exports and theme switching.
    public static func claim(seconds: Double, at date: Date = Date(), calendar: Calendar = .current,
                             storage: any PreferenceStorage = ApplicationPreferences.current) -> Bool {
        guard FocusMilestone(seconds: seconds) == .achieved else { return false }
        let today = day(at: date, calendar: calendar)
        guard storage.object(forKey: key) as? String != today else { return false }
        storage.set(today, forKey: key)
        return storage.object(forKey: key) as? String == today
    }
}
