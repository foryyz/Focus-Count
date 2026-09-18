import Foundation
import FocusCountCore

/// Calendar dates use the viewer's local time zone; spacing uses elapsed time.
struct EventAnalytics {
    struct Frequency: Identifiable {
        let id: String
        let count: Int
        let weeksPerOccurrence: Double?
    }
    struct Bucket: Identifiable {
        let interval: DateInterval
        let count: Int
        var id: Date { interval.start }
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
    static func buckets(_ events: [TimeEvent], component: Calendar.Component, calendar: Calendar = .current) -> [Bucket] {
        Dictionary(grouping: events, by: { calendar.dateInterval(of: component, for: $0.occurredAt)!.start })
            .map { Bucket(interval: calendar.dateInterval(of: component, for: $0.key)!, count: $0.value.count) }
            .sorted { $0.id < $1.id }
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
    struct TrendPoint: Identifiable {
        let id: Int
        let date: Date
        let count: Int
    }
    static func trend(_ events: [TimeEvent], start: Date, end: Date, cumulative: Bool, component: Calendar.Component, calendar: Calendar = .current) -> [TrendPoint] {
        let sorted = events.filter { $0.deletedAt == nil && $0.occurredAt >= start && $0.occurredAt < end }.sorted { $0.occurredAt < $1.occurredAt }
        if cumulative {
            var points = [TrendPoint(id: 0, date: start, count: 0)]
            for (index, event) in sorted.enumerated() { points.append(TrendPoint(id: index + 1, date: event.occurredAt, count: index + 1)) }
            points.append(TrendPoint(id: points.count, date: end, count: sorted.count))
            return points
        }
        let counts = Dictionary(uniqueKeysWithValues: buckets(sorted, component: component, calendar: calendar).map { ($0.id, $0.count) })
        var date = calendar.dateInterval(of: component, for: start)!.start
        var points: [TrendPoint] = []
        while date < end {
            points.append(TrendPoint(id: points.count, date: max(date, start), count: counts[date] ?? 0))
            guard let next = calendar.dateInterval(of: component, for: date)?.end, next > date else { break }
            date = next
        }
        return points
    }

}
