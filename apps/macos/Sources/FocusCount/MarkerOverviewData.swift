import Foundation
import FocusCountCore

/// Calendar buckets are half-open and always use Monday as the start of a week.
enum MarkerGranularity: String, CaseIterable, Identifiable {
    case automatic = "自动", day = "按天", week = "按周", month = "按月"
    var id: String { rawValue }
    func resolved(days: Int) -> Self {
        self == .automatic ? (days <= 45 ? .day : days <= 280 ? .week : .month) : self
    }
}

struct MarkerOverviewData {
    struct Bucket: Identifiable {
        let start: Date
        let end: Date
        let partial: Bool
        var id: Date { start }
    }
    struct Cell: Identifiable {
        let kind: String
        let bucket: Bucket
        let events: [TimeEvent]
        var id: String { kind + ":" + String(bucket.start.timeIntervalSinceReferenceDate) }
    }
    let buckets: [Bucket]
    let cells: [Cell]
    let names: [String]
    let granularity: MarkerGranularity
    init(events: [TimeEvent], start: Date, end: Date, granularity: MarkerGranularity, now: Date = Date(), calendar: Calendar = .current) {
        let span = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        self.granularity = granularity.resolved(days: span)
        let unit: Calendar.Component = self.granularity == .month ? .month : self.granularity == .week ? .weekOfYear : .day
        var cal = calendar
        cal.firstWeekday = 2
        var cursor = cal.dateInterval(of: unit, for: start)!.start
        var buckets: [Bucket] = []
        while cursor < end {
            let next = cal.date(byAdding: unit, value: 1, to: cursor)!
            buckets.append(Bucket(start: max(start, cursor), end: min(end, next), partial: unit != .day && (cursor < start || next > end || next > now)))
            cursor = next
        }
        self.buckets = buckets
        let active = events.filter { $0.deletedAt == nil && $0.occurredAt >= start && $0.occurredAt < end && $0.occurredAt <= now }
        names = Array(Set(active.map { EventAnalytics.label($0.kind) })).sorted()
        let grouped = Dictionary(grouping: active) { event in
            max(start, cal.dateInterval(of: unit, for: event.occurredAt)!.start)
        }
        cells = buckets.flatMap { bucket in
            Dictionary(grouping: grouped[bucket.start] ?? [], by: { EventAnalytics.label($0.kind) }).map { kind, values in
                Cell(kind: kind, bucket: bucket, events: values.sorted { $0.occurredAt > $1.occurredAt })
            }.sorted { $0.kind < $1.kind }
        }
    }
    // A single scale across every row; bubble area is proportional to count until capped.
    static func diameter(count: Int, unit: Double, limit: Double) -> Double {
        min(limit, unit * sqrt(Double(max(0, count))))
    }
}
