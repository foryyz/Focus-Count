import Foundation
import FocusCountCore

/// Calendar dates use the viewer's local time zone; spacing uses elapsed time.
struct EventAnalytics {
    struct Frequency: Identifiable {
        let id: String
        let count: Int
    }
    static func label(_ kind: String) -> String {
        kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func records(_ events: [TimeEvent], days: Int?, now: Date = Date(), calendar: Calendar = .current) -> [TimeEvent] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let start = days.map { calendar.date(byAdding: .day, value: 1 - $0, to: calendar.startOfDay(for: now))! } ?? .distantPast
        return events.filter { $0.deletedAt == nil && (days == nil || ($0.occurredAt >= start && $0.occurredAt < end)) }
            .sorted { $0.occurredAt == $1.occurredAt ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt > $1.occurredAt }
    }
    static func frequencies(_ events: [TimeEvent]) -> [Frequency] {
        Dictionary(grouping: events.filter { $0.deletedAt == nil }, by: { label($0.kind) }).map { kind, values in
            return Frequency(id: kind, count: values.count)
        }.sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }
    static func periodStart(range: Int, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard range != 0 else { return nil }
        let today = calendar.startOfDay(for: now)
        if range == -1 {
            let weekday = calendar.component(.weekday, from: today)
            return calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        }
        return calendar.date(byAdding: .day, value: 1 - range, to: today)!
    }
    static func hours(_ events: [TimeEvent], calendar: Calendar = .current) -> [Int] {
        var counts = Array(repeating: 0, count: 24)
        for event in events where event.deletedAt == nil { counts[calendar.component(.hour, from: event.occurredAt)] += 1 }
        return counts
    }
    static func weeklyRate(count: Int, start: Date, now: Date = Date(), calendar: Calendar = .current) -> Double {
        let days = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0) + 1)
        return Double(count) * 7 / Double(days)
    }
    static func weeklyText(_ value: Double) -> String {
        "每周 " + value.formatted(.number.precision(.fractionLength(0...2))) + " 次"
    }
    struct DailyCount: Identifiable {
        var id: String { kind + "-" + String(day.timeIntervalSinceReferenceDate) }
        let kind: String
        let day: Date
        let count: Int
    }
    static func dailyCounts(_ events: [TimeEvent], calendar: Calendar = .current) -> [DailyCount] {
        let groups = Dictionary(grouping: events.filter { $0.deletedAt == nil }, by: { label($0.kind) })
        var result: [DailyCount] = []
        for (kind, values) in groups {
            let days = Dictionary(grouping: values, by: { calendar.startOfDay(for: $0.occurredAt) })
            for (day, entries) in days { result.append(DailyCount(kind: kind, day: day, count: entries.count)) }
        }
        return result.sorted { $0.day == $1.day ? $0.kind < $1.kind : $0.day < $1.day }
    }
}
