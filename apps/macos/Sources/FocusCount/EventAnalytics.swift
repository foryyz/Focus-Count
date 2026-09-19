import Foundation
import FocusCountCore

/// Calendar dates use the viewer's local time zone; spacing uses elapsed time.
struct EventAnalytics {
    struct Frequency: Identifiable {
        let id: String
        let count: Int
        let weeksPerOccurrence: Double?
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
            let dates = values.map(\.occurredAt).sorted()
            let average = dates.count > 1 ? dates.last!.timeIntervalSince(dates.first!) / Double(dates.count - 1) / (7 * 86400) : nil
            return Frequency(id: kind, count: dates.count, weeksPerOccurrence: average)
        }.sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }
    static func intervalText(_ weeks: Double?) -> String {
        guard let weeks else { return "暂无间隔" }
        if weeks == 0 { return "0 周／次" }
        if weeks < 0.01 { return "< 0.01 周／次" }
        return weeks.formatted(.number.precision(.fractionLength(0...2))) + " 周／次"
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
}
