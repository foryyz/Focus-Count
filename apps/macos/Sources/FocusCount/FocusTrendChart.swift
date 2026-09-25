import SwiftUI
import Charts
import FocusCountCore

struct FocusTrendChart: View {
    let buckets: [FocusBucket]
    let interval: DateInterval
    let week: Bool
    let color: Color
    let averageRecords: [StudySession]
    @Binding var selected: Date?
    @State private var hovered: Date?
    @State private var showAverage = false
    private var points: [FocusBucket] { buckets.filter { $0.start <= Date() } }
    private var daily: Bool { FocusAnalysisData.grain(interval) == .day }
    private var canAverage: Bool { daily && buckets.count > 7 }
    private var averages: [Date: Double] { canAverage && showAverage ? FocusAnalysisData.trailingWeekAverage(averageRecords, days: points.map(\.start)) : [:] }
    private var inspected: FocusBucket? { buckets.first { $0.start == (hovered ?? selected) } }
    private var peak: Double { max(1, max(points.map(\.seconds).max() ?? 0, averages.values.max() ?? 0) / 3600 * (week ? 1.3 : 1.15)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(daily ? "每日投入" : "投入趋势").font(.headline)
                Text(daily ? "有效专注时长" : "按\(FocusAnalysisData.grain(interval).rawValue)汇总").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if canAverage { Toggle("7 日平均", isOn: $showAverage).toggleStyle(.checkbox).font(.caption) }
            }
            HStack {
                if let bucket = inspected {
                    Text(label(bucket)).fontWeight(.medium)
                    Text(bucket.start > Date() ? "尚未到来" : "\(shortDuration(bucket.seconds)) · \(bucket.records.count) 次")
                    if let average = averages[bucket.start] { Text("7 日平均 \(shortDuration(average))") }
                } else { Text("\(week ? "每日时长直接标注" : "悬停查看时长") · 点击日期查看记录") }
                Spacer()
            }.font(.caption).foregroundStyle(.secondary).frame(height: 18)
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("日期", midpoint(point)), y: .value("小时", point.seconds / 3600))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("日期", midpoint(point)), y: .value("小时", point.seconds / 3600), series: .value("曲线", "投入"))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                        .accessibilityLabel("\(label(point))，\(shortDuration(point.seconds))")
                    if week || points.count == 1 || point.start == inspected?.start || Calendar.current.isDateInToday(point.start) {
                        PointMark(x: .value("日期", midpoint(point)), y: .value("小时", point.seconds / 3600))
                            .foregroundStyle(color).symbolSize(Calendar.current.isDateInToday(point.start) ? 65 : 28)
                            .annotation(position: .top, spacing: 8) {
                                if week { Text(shortDuration(point.seconds)).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Color.primary) }
                            }
                    }
                    if let average = averages[point.start] {
                        LineMark(x: .value("日期", midpoint(point)), y: .value("小时", average / 3600), series: .value("曲线", "7日平均"))
                            .foregroundStyle(color.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .interpolationMethod(.linear)
                    }
                }
                if let point = inspected {
                    RuleMark(x: .value("查看日期", midpoint(point))).foregroundStyle(Color.secondary.opacity(0.3)).lineStyle(StrokeStyle(dash: [3, 4]))
                }
            }
            .chartXScale(domain: interval.start...interval.end)
            .chartYScale(domain: 0...peak)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisValueLabel { if let hours = value.as(Double.self) { Text(hours.formatted(.number.precision(.fractionLength(0...1))) + "h").font(.caption2) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisTick().foregroundStyle(Color.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let date = value.as(Date.self), let point = buckets.first(where: { midpoint($0) == date }) {
                            Text(week ? weekday(point.start) : axisLabel(point.start)).font(.caption2)
                                .foregroundStyle(point.start > Date() ? Color.secondary.opacity(0.4) : Color.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location): hovered = point(at: location, proxy: proxy, geometry: geometry)
                            case .ended: hovered = nil
                            }
                        }
                        .gesture(DragGesture(minimumDistance: 0).onEnded { event in selected = point(at: event.location, proxy: proxy, geometry: geometry) })
                }
            }
            if canAverage && showAverage {
                Text("虚线：当天及此前 6 个自然日的平均时长，包含无记录日期。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.onChange(of: interval) { _ in hovered = nil }
    }
    private func point(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Date? {
        let plot = geometry[proxy.plotAreaFrame]
        guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX) else { return nil }
        return buckets.first { date >= $0.start && date < $0.end }?.start
    }
    private func midpoint(_ bucket: FocusBucket) -> Date { bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2) }
    private var axisDates: [Date] {
        let stride = max(1, Int(ceil(Double(buckets.count) / 8)))
        var indices = Array(Swift.stride(from: 0, to: buckets.count, by: stride))
        if let last = buckets.indices.last, indices.last != last {
            if let previous = indices.last, last - previous < max(1, stride / 2) { indices.removeLast() }
            indices.append(last)
        }
        return indices.map { midpoint(buckets[$0]) }
    }
    private func weekday(_ date: Date) -> String { ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: date) - 1] }
    private func axisLabel(_ date: Date) -> String { FocusAnalysisData.grain(interval) == .month ? date.formatted(.dateTime.year().month()) : date.formatted(.dateTime.month().day()) }
    private func label(_ bucket: FocusBucket) -> String {
        let start = bucket.start.formatted(date: .abbreviated, time: .omitted)
        return daily ? start : start + " — " + bucket.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
    }
    private func shortDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        if seconds > 0 && minutes == 0 { return "<1m" }
        return minutes >= 60 ? "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)m") : "\(minutes)m"
    }
}
