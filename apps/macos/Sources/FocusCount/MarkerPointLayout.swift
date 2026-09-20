import Foundation
import FocusCountCore

struct MarkerPointLayout {
    struct Item: Identifiable {
        let events: [TimeEvent]
        let x: Double
        let y: Double
        let grouped: Bool
        let anchorY: Double
        let diameter: Double
        var id: UUID { events[0].id }
    }
    static func items(events: [TimeEvent], start: Date, offset: Double, visibleDays: Double, width: Double, hourHeight: Double = 30, calendar: Calendar = .current) -> [Item] {
        let dayWidth = width / max(1, visibleDays)
        let height = 24 * hourHeight
        func day(_ event: TimeEvent) -> Int { calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: event.occurredAt)).day ?? 0 }
        func y(_ event: TimeEvent) -> Double {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: event.occurredAt)
            return (Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600) * hourHeight
        }
        let valid = events.filter { $0.deletedAt == nil && Double(day($0)) >= floor(offset) && Double(day($0)) < ceil(offset + visibleDays) }
        var result: [Item] = []
        for (column, entries) in Dictionary(grouping: valid, by: day) {
            let sorted = entries.sorted { y($0) == y($1) ? $0.id.uuidString < $1.id.uuidString : y($0) < y($1) }
            var clusters: [[TimeEvent]] = []
            for event in sorted {
                if let last = clusters.last?.last, y(event) - y(last) < 27 { clusters[clusters.count - 1].append(event) }
                else { clusters.append([event]) }
            }
            let center = (Double(column) + 0.5 - offset) * dayWidth
            let capacity = max(1, Int((dayWidth - 12) / 27))
            var placed: [Item] = []
            for cluster in clusters {
                // Reuse lanes when possible, keeping every record at its exact time.
                var laneEnds = Array(repeating: -Double.infinity, count: capacity)
                var lanes: [Int] = []
                for event in cluster {
                    if let lane = laneEnds.firstIndex(where: { y(event) - $0 >= 27 }) { lanes.append(lane); laneEnds[lane] = y(event) }
                    else { break }
                }
                let groups: [[TimeEvent]]
                if lanes.count == cluster.count { groups = cluster.map { [$0] } }
                else {
                    groups = Dictionary(grouping: cluster, by: { EventAnalytics.label($0.kind) }).values.sorted { $0[0].id.uuidString < $1[0].id.uuidString }
                }
                for (index, group) in groups.enumerated() {
                    let anchor = group.map(y).reduce(0, +) / Double(group.count)
                    let diameter = group.count == 1 ? 24.0 : min(72, 34 + sqrt(Double(group.count - 1)) * 10)
                    let columns = max(1, Int((dayWidth - 10) / (diameter + 4)))
                    let preferredLane = lanes.count == cluster.count ? lanes[index] : index % columns
                    let usedColumns = lanes.count == cluster.count ? max(1, (lanes.max() ?? 0) + 1) : columns
                    var candidates: [(Double, Double)] = []
                    for displacement in 0...Int(ceil(height / 8)) {
                        for sign in displacement == 0 ? [1.0] : [-1.0, 1.0] {
                            let targetY = min(height - diameter / 2, max(diameter / 2, anchor + Double(displacement) * 8 * sign))
                            for lane in 0..<usedColumns {
                                let currentLane = (lane + preferredLane) % usedColumns
                                let targetX = center + (Double(currentLane) - Double(usedColumns - 1) / 2) * (diameter + 4)
                                candidates.append((targetX, targetY))
                            }
                        }
                    }
                    let position = candidates.first { x, yy in
                        !placed.contains { abs($0.x - x) < ($0.diameter + diameter) / 2 + 3 && abs($0.y - yy) < ($0.diameter + diameter) / 2 + 3 }
                    } ?? (center, min(height - diameter / 2, max(diameter / 2, anchor)))
                    placed.append(Item(events: group, x: position.0, y: position.1, grouped: group.count > 1, anchorY: anchor, diameter: diameter))
                }
            }
            result += placed
        }
        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
