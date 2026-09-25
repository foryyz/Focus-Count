import Foundation
import FocusCountCore

struct FocusCategory: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
}

struct FocusAppearance: Codable {
    var categories: [FocusCategory] = []
    var assignments: [String: UUID] = [:]
    var colors: [String: String] = [:]
}

struct FocusBucket: Identifiable {
    var start: Date
    var end: Date
    var records: [StudySession]
    var id: Date { start }
    var seconds: Double { records.reduce(0) { $0 + $1.activeSeconds } }
}

struct FocusBreakdown: Identifiable {
    var name: String
    var records: [StudySession]
    var id: String { name }
    var seconds: Double { records.reduce(0) { $0 + $1.activeSeconds } }
}

enum FocusAnalysisData {
    enum Period: String, CaseIterable { case week = "本周", month = "30 天", quarter = "90 天", all = "全部", custom = "自定义" }
    enum Grain: String { case day = "天", week = "周", month = "月" }
    static func interval(_ period: Period, records: [StudySession], now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let start: Date
        switch period {
        case .week:
            let offset = (calendar.component(.weekday, from: today) + 5) % 7
            start = calendar.date(byAdding: .day, value: -offset, to: today)!
        case .month: start = calendar.date(byAdding: .day, value: -29, to: today)!
        case .quarter: start = calendar.date(byAdding: .day, value: -89, to: today)!
        case .all: start = min(today, calendar.startOfDay(for: records.filter { $0.deletedAt == nil }.map(\.startedAt).min() ?? today))
        case .custom: start = today
        }
        return DateInterval(start: start, end: end)
    }
    static func contains(_ interval: DateInterval, _ date: Date) -> Bool { date >= interval.start && date < interval.end }
    static func filtered(_ records: [StudySession], interval: DateInterval) -> [StudySession] {
        records.filter { $0.deletedAt == nil && contains(interval, $0.startedAt) }
    }
    static func dayCount(_ interval: DateInterval, calendar: Calendar = .current) -> Int {
        max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
    }
    static func grain(_ interval: DateInterval, calendar: Calendar = .current) -> Grain {
        let days = dayCount(interval, calendar: calendar)
        return days <= 90 ? .day : days <= 730 ? .week : .month
    }
    static func buckets(_ records: [StudySession], interval: DateInterval, calendar: Calendar = .current) -> [FocusBucket] {
        let grain = grain(interval, calendar: calendar)
        var calendar = calendar
        calendar.firstWeekday = 2
        let component: Calendar.Component = grain == .day ? .day : grain == .week ? .weekOfYear : .month
        var start = interval.start
        var result: [FocusBucket] = []
        let valid = filtered(records, interval: interval).sorted { $0.startedAt < $1.startedAt }
        var index = 0
        while start < interval.end {
            guard let boundary = calendar.dateInterval(of: component, for: start)?.end, boundary > start else { break }
            let end = min(interval.end, boundary)
            var values: [StudySession] = []
            while index < valid.count && valid[index].startedAt < end {
                values.append(valid[index]); index += 1
            }
            result.append(FocusBucket(start: start, end: end, records: values))
            start = end
        }
        return result
    }
    static func breakdown(_ records: [StudySession], key: (StudySession) -> String) -> [FocusBreakdown] {
        Dictionary(grouping: records, by: key).map { FocusBreakdown(name: $0.key, records: $0.value) }
            .sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
    }
}
