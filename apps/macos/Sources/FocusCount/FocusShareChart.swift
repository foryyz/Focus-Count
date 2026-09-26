import SwiftUI

struct FocusShareSlice: Identifiable {
    let id: String
    let name: String
    let seconds: Double
    let source: FocusBreakdown?
    static func make(_ items: [FocusBreakdown]) -> [FocusShareSlice] {
        let positive = items.filter { $0.seconds > 0 }
        let limit = positive.count > 6 ? 5 : 6
        var result = positive.prefix(limit).map { FocusShareSlice(id: "item:" + $0.id, name: $0.name, seconds: $0.seconds, source: $0) }
        if positive.count > 6 {
            let rest = positive.dropFirst(5)
            result.append(FocusShareSlice(id: "remainder", name: "其他（\(rest.count)项）", seconds: rest.reduce(0) { $0 + $1.seconds }, source: nil))
        }
        return result
    }
}

struct FocusShareChart: View {
    let items: [FocusBreakdown]
    let activityCount: Int
    let pie: Bool
    let color: (FocusBreakdown) -> Color
    private var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    private var slices: [FocusShareSlice] { FocusShareSlice.make(items) }
    private var total: Double { items.reduce(0) { $0 + $1.seconds } }
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.height - 12, geometry.size.width * (pie ? 0.55 : 0.78))
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Circle().fill(Color.secondary.opacity(0.08)).frame(width: size, height: size).position(center)
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    let start = slices.prefix(index).reduce(0) { $0 + $1.seconds } / (total > 0 ? total : 1)
                    let end = start + slice.seconds / (total > 0 ? total : 1)
                    let middle = (start + end) * Double.pi - Double.pi / 2
                    ShareSector(start: start, end: end, hole: pie ? 0 : 0.70)
                        .fill(slice.source.map(color) ?? Color.secondary)
                        .frame(width: size, height: size).position(center)
                        .help("\(slice.name) · \(duration(slice.seconds)) · \(percent(slice.seconds))")
                        .accessibilityLabel("\(slice.name)，\(percent(slice.seconds))，\(duration(slice.seconds))")
                    if pie && slice.seconds / (total > 0 ? total : 1) >= 0.12 {
                        VStack(spacing: 2) {
                            Text(slice.name).lineLimit(1)
                            Text(percent(slice.seconds)).fontWeight(.semibold).monospacedDigit()
                        }.font(.system(size: size < 180 ? 10 : 12)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.7), radius: 2)
                            .frame(width: max(42, size * 0.36))
                            .position(x: center.x + cos(middle) * size * 0.29, y: center.y + sin(middle) * size * 0.29)
                            .help(slice.name)
                    } else if pie {
                        let right = cos(middle) >= 0
                        let indices = slices.indices.filter { candidate in
                            let offset = slices.prefix(candidate).reduce(0) { $0 + $1.seconds }
                            let angle = (offset + slices[candidate].seconds / 2) / (total > 0 ? total : 1) * Double.pi * 2 - Double.pi / 2
                            return (cos(angle) >= 0) == right
                        }.sorted { left, rightIndex in angleY(left) < angleY(rightIndex) }
                        let rank = indices.firstIndex(of: index) ?? 0
                        let y = geometry.size.height * Double(rank + 1) / Double(indices.count + 1)
                        let labelX = right ? geometry.size.width - 43 : 43
                        Path { path in
                            path.move(to: CGPoint(x: center.x + cos(middle) * size / 2, y: center.y + sin(middle) * size / 2))
                            path.addLine(to: CGPoint(x: right ? labelX - 40 : labelX + 40, y: y))
                        }.stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        VStack(spacing: 2) {
                            Text(slice.name).lineLimit(1).help(slice.name)
                            Text(percent(slice.seconds)).fontWeight(.semibold).monospacedDigit()
                        }.font(.caption).frame(width: 82).position(x: labelX, y: y)
                    }
                }
                if !pie || total == 0 {
                    if !pie { Circle().fill(background).frame(width: size * 0.70, height: size * 0.70).position(center) }
                    VStack(spacing: 6) {
                        Text("\(activityCount) 个活动").font(.caption).foregroundStyle(.secondary)
                        Text(duration(total)).font(.system(size: size > 190 ? 22 : 15, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("总有效时长").font(.caption2).foregroundStyle(.secondary)
                    }.position(center).allowsHitTesting(false)
                }
            }
        }
    }
    private func angleY(_ index: Int) -> Double {
        let start = slices.prefix(index).reduce(0) { $0 + $1.seconds }
        return sin((start + slices[index].seconds / 2) / (total > 0 ? total : 1) * Double.pi * 2 - Double.pi / 2)
    }
    private func percent(_ seconds: Double) -> String {
        guard total > 0 else { return "0%" }
        let value = seconds / total * 100
        return value < 1 && value > 0 ? "<1%" : String(format: "%.0f%%", value)
    }
}

private struct ShareSector: Shape {
    let start: Double
    let end: Double
    let hole: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        if hole == 0 { path.addLine(to: center) }
        else { path.addArc(center: center, radius: radius * hole, startAngle: .degrees(end * 360 - 90), endAngle: .degrees(start * 360 - 90), clockwise: true) }
        path.closeSubpath()
        return path
    }
}

struct FocusLargeDailyBars: View {
    let buckets: [FocusBucket]
    let color: Color
    let week: Bool
    @Binding var selected: Date?
    var body: some View {
        GeometryReader { geometry in
            let peak = max(1, buckets.map(\.seconds).max() ?? 0)
            let width = max(52, (geometry.size.width - 12) / Double(max(1, buckets.count)))
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(buckets) { bucket in
                        Button { selected = bucket.start } label: {
                            VStack(spacing: 10) {
                                Text(bucket.start > Date() ? "—" : shortDuration(bucket.seconds)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 5).fill(color.opacity(selected == bucket.start ? 1 : 0.75))
                                    .frame(width: min(48, width * 0.62), height: bucket.seconds == 0 ? 2 : max(2, (geometry.size.height - 75) * bucket.seconds / peak))
                                Text(label(bucket)).font(.caption2).foregroundStyle(.secondary)
                            }.frame(width: width, height: max(60, geometry.size.height - 14), alignment: .bottom)
                        }.buttonStyle(.plain).help("\(bucket.start.formatted(date: .complete, time: .omitted)) · \(duration(bucket.seconds))")
                    }
                }
            }
        }
    }
    private func label(_ bucket: FocusBucket) -> String {
        if week { return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: bucket.start) - 1] }
        return bucket.start.formatted(.dateTime.month().day())
    }
    private func shortDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
