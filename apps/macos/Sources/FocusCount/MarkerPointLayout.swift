import Foundation
import FocusCountCore

/// Each record appears either as an individual mark or once inside an expandable group.
struct MarkerPointLayout {
    struct Item: Identifiable {
        let events: [TimeEvent]
        let x: Double
        let y: Double
        let grouped: Bool
        var id: UUID { events[0].id }
    }
    static func items(events: [TimeEvent], start: Date, offset: Double, visibleDays: Double, width: Double, hourHeight: Double = 30, calendar: Calendar = .current) -> [Item] {
        let dayWidth = width / max(1, visibleDays)
        let stride = max(1, Int(ceil(36 / dayWidth)))
        func day(_ event: TimeEvent) -> Int { calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: event.occurredAt)).day ?? 0 }
        func y(_ event: TimeEvent) -> Double {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: event.occurredAt)
            return (Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600) * hourHeight
        }
        let valid = events.filter { $0.deletedAt == nil && Double(day($0)) >= floor(offset) && Double(day($0)) < ceil(offset + visibleDays) }
        let columns = Dictionary(grouping: valid, by: { day($0) / stride })
        var result: [Item] = []
        for (column, entries) in columns {
            let sorted = entries.sorted { y($0) == y($1) ? $0.id.uuidString < $1.id.uuidString : y($0) < y($1) }
            var clusters: [[TimeEvent]] = []
            for event in sorted {
                if let last = clusters.last?.last, y(event) - y(last) < 26 { clusters[clusters.count - 1].append(event) }
                else { clusters.append([event]) }
            }
            let center = min(width - 16, max(16, (Double(column * stride) + Double(stride) / 2 - offset) * dayWidth))
            let capacity = max(1, Int((dayWidth - 8) / 26))
            for cluster in clusters {
                if stride > 1 || cluster.count > capacity {
                    result.append(Item(events: cluster, x: center, y: cluster.map(y).reduce(0, +) / Double(cluster.count), grouped: true))
                } else {
                    for (index, event) in cluster.enumerated() {
                        let x = center + (Double(index) - Double(cluster.count - 1) / 2) * 26
                        result.append(Item(events: [event], x: x, y: y(event), grouped: false))
                    }
                }
            }
        }
        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
