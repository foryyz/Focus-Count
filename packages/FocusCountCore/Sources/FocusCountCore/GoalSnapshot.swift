import Foundation

/// A single shared target. Visibility is deliberately absent: it belongs to each device.
public struct GoalSnapshot: Codable, Equatable {
    public var name: String
    public var emoji: String
    public var date: Date
    public var includesTime: Bool
    public var deleted: Bool
    public var updatedAt: Date
    public var revision: UUID
    public init(name: String, emoji: String = "", date: Date, includesTime: Bool = false, deleted: Bool = false, updatedAt: Date = Date(), revision: UUID = UUID()) {
        self.name = name; self.emoji = emoji; self.date = date; self.includesTime = includesTime
        self.deleted = deleted; self.updatedAt = updatedAt; self.revision = revision
    }
    public var isValid: Bool {
        date.timeIntervalSinceReferenceDate.isFinite && updatedAt.timeIntervalSinceReferenceDate.isFinite &&
        (deleted || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && name.count <= 500 && emoji.count <= 16
    }
    public static func merge(_ local: Self?, _ incoming: Self?) -> Self? {
        guard let local else { return incoming }
        guard let incoming else { return local }
        if local.updatedAt != incoming.updatedAt { return local.updatedAt > incoming.updatedAt ? local : incoming }
        // Stable even if files reuse a revision with different content.
        func key(_ value: Self) -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return String(data: (try? encoder.encode(value)) ?? Data(), encoding: .utf8) ?? ""
        }
        return key(local) >= key(incoming) ? local : incoming
    }
}
