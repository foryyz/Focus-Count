import SwiftUI
import FocusCountCore

struct MarkerTimelineChart: View {
    let events: [TimeEvent]
    let start: Date
    let end: Date
    @ObservedObject var colors: MarkerColors
    let isWeek: Bool
    let line: Bool
    @State private var zoom = 1.0
    @State private var offset = 0.0
    @State private var hoverDay: Int?
    @State private var dragStart: Double?
    @State private var pinchStart: Double?
    private var calendar: Calendar { .current }
    private var recordedDays: Int { max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1) }
    private var days: Int { isWeek ? 7 : recordedDays }
    private var minZoom: Double { line ? 1 : max(1, Double(days) / 4) }
    private var maxZoom: Double { max(1, Double(days)) }
    private var visible: Double { Double(days) / zoom }
    private var maxOffset: Double { max(0, Double(days) - visible) }
    private var data: [EventAnalytics.DailyCount] { EventAnalytics.dailyCounts(events) }
    private var names: [String] { Array(Set(data.map(\.kind))).sorted() }
    private var maximum: Int { max(1, data.map(\.count).max() ?? 1) }
    private func dayIndex(_ date: Date) -> Int { calendar.dateComponents([.day], from: start, to: date).day ?? 0 }
    private func date(_ index: Int) -> Date { calendar.date(byAdding: .day, value: index, to: start)! }
    private func dayLabel(_ index: Int) -> String {
        if isWeek { return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: date(index)) - 1] }
        return date(index).formatted(.dateTime.month().day())
    }
    private func updateZoom(_ value: Double) {
        let center = offset + visible / 2
        zoom = min(maxZoom, max(minZoom, value))
        offset = min(maxOffset, max(0, center - visible / 2))
        hoverDay = nil
    }
    private func resetWindow() {
        zoom = minZoom
        let recent = events.map { dayIndex($0.occurredAt) }.max() ?? recordedDays - 1
        offset = line ? 0 : min(maxOffset, max(0, Double(recent + 1) - visible))
        hoverDay = nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button { updateZoom(zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }.disabled(zoom <= minZoom).help("缩小")
                Text(zoom.formatted(.number.precision(.fractionLength(1))) + "×").font(.caption.monospacedDigit()).frame(width: 45)
                Button { updateZoom(zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }.disabled(zoom >= maxZoom).help("放大")
                Button(line ? "完整时间轴" : "最近标记") { resetWindow() }
            }
            Text(start.formatted(date: .abbreviated, time: .omitted) + " — " + end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted) + " · 统计 \(recordedDays) 天")
                .font(.caption).foregroundStyle(.secondary)
            if !line {
                MarkerPointTimeline(events: events, start: start, days: days, offset: offset, visibleDays: visible, isWeek: isWeek, colors: colors) { first, last in
                    let firstDay = dayIndex(calendar.startOfDay(for: first))
                    let lastDay = dayIndex(calendar.startOfDay(for: last))
                    updateZoom(Double(days) / Double(max(1, lastDay - firstDay + 1)))
                    offset = min(maxOffset, max(0, Double(firstDay)))
                }
            } else {
            GeometryReader { geometry in
                Canvas { context, size in
                    let plot = CGRect(x: 35, y: 25, width: max(1, size.width - 55), height: max(1, size.height - 70))
                    func x(_ day: Double) -> Double { plot.minX + (day - offset) / visible * plot.width }
                    func y(_ count: Int) -> Double { plot.maxY - Double(count) / Double(maximum) * (plot.height - 25) }
                    let low = max(0, Int(floor(offset)))
                    let high = min(days - 1, Int(ceil(offset + visible)))
                    let tickStep = max(1, Int(ceil(visible / 8)))
                    for index in low...max(low, high) where index % tickStep == 0 {
                        let position = x(Double(index) + 0.5)
                        guard position >= plot.minX && position <= plot.maxX else { continue }
                        var grid = Path(); grid.move(to: CGPoint(x: position, y: plot.minY)); grid.addLine(to: CGPoint(x: position, y: plot.maxY))
                        context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 1)
                        context.draw(Text(dayLabel(index)).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary), at: CGPoint(x: position, y: plot.maxY + 17))
                    }
                    let step = max(1, Int(ceil(Double(maximum) / 4)))
                    for count in stride(from: 0, through: maximum, by: step) {
                        var grid = Path(); grid.move(to: CGPoint(x: plot.minX, y: y(count))); grid.addLine(to: CGPoint(x: plot.maxX, y: y(count)))
                        context.stroke(grid, with: .color(.secondary.opacity(0.16)), lineWidth: 1)
                        context.draw(Text("\(count)").font(.system(size: 11)).foregroundColor(.secondary), at: CGPoint(x: 22, y: y(count)), anchor: .trailing)
                    }
                    context.draw(Text("次／天").font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: 3, y: 7), anchor: .leading)
                    context.stroke(Path(plot), with: .color(.secondary.opacity(0.3)), lineWidth: 1)
                    var marks = context
                    marks.clip(to: Path(plot))
                    for name in names {
                        let entries = data.filter { $0.kind == name }
                        let counts = Dictionary(uniqueKeysWithValues: entries.map { (dayIndex($0.day), $0.count) })
                        if line {
                            var path = Path()
                            for index in max(0, min(recordedDays - 1, low - 1))...min(recordedDays - 1, high + 1) {
                                let point = CGPoint(x: x(Double(index) + 0.5), y: y(counts[index] ?? 0))
                                if index == max(0, min(recordedDays - 1, low - 1)) { path.move(to: point) } else { path.addLine(to: point) }
                            }
                            marks.stroke(path, with: .color(colors.color(name)), lineWidth: 2)
                        }
                        for entry in entries {
                            let day = dayIndex(entry.day)
                            guard day >= low - 1 && day <= high + 1 else { continue }
                            let position = CGPoint(x: x(Double(day) + 0.5), y: y(entry.count))
                            if !line, let emoji = colors.emojis[name], !emoji.isEmpty {
                                let diameter = min(40, 17 + sqrt(Double(entry.count)) * 5)
                                marks.draw(Text(emoji).font(.system(size: diameter)), at: position)
                            } else {
                                let diameter = line ? 5 : min(32, 7 + sqrt(Double(entry.count)) * 5)
                                let circle = Path(ellipseIn: CGRect(x: position.x - diameter / 2, y: position.y - diameter / 2, width: diameter, height: diameter))
                                marks.fill(circle, with: .color(colors.color(name).opacity(0.85)))
                                marks.stroke(circle, with: .color(colors.color(name)), lineWidth: 1)
                            }
                        }
                    }
                    if let hoverDay {
                        var rule = Path(); rule.move(to: CGPoint(x: x(Double(hoverDay) + 0.5), y: plot.minY)); rule.addLine(to: CGPoint(x: x(Double(hoverDay) + 0.5), y: plot.maxY))
                        marks.stroke(rule, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let fraction = (location.x - 35) / max(1, geometry.size.width - 55)
                        hoverDay = fraction >= 0 && fraction <= 1 ? min(days - 1, max(0, Int(floor(offset + fraction * visible)))) : nil
                    case .ended: hoverDay = nil
                    }
                }
                .gesture(DragGesture().onChanged { value in
                    if dragStart == nil { dragStart = offset }
                    offset = min(maxOffset, max(0, (dragStart ?? offset) - value.translation.width / max(1, geometry.size.width - 55) * visible))
                    hoverDay = nil
                }.onEnded { _ in dragStart = nil })
                .simultaneousGesture(MagnificationGesture().onChanged { value in
                    if pinchStart == nil { pinchStart = zoom }
                    updateZoom((pinchStart ?? zoom) * value)
                }.onEnded { _ in pinchStart = nil })
                .accessibilityLabel("每日标记次数，可使用下方日期滑块浏览。具体记录见时间轴页。")
            }.frame(minHeight: 240, maxHeight: .infinity)
            }
            if !line {
                MarkerRangeNavigator(days: days, start: start, visible: visible, offset: offset) { position, span in
                    zoom = min(maxZoom, max(minZoom, Double(days) / span))
                    offset = min(maxOffset, max(0, position))
                }
            }
            if line && maxOffset > 0 {
                HStack {
                    Text("浏览日期").font(.caption)
                    Slider(value: $offset, in: 0...maxOffset).accessibilityLabel("时间轴位置")
                }
            }
            if line, let hoverDay {
                let entries = data.filter { dayIndex($0.day) == hoverDay }
                Text(date(hoverDay).formatted(date: .abbreviated, time: .omitted) + " · " + (hoverDay >= recordedDays ? "尚未到来" : entries.isEmpty ? "无标记" : entries.map { ($0.kind) + " \($0.count) 次" }.joined(separator: "    ")))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 32, alignment: .topLeading)
            } else {
                Text(line ? "线图按每天总次数显示；放大后拖动或使用滑块浏览。" : "全天一屏 · 优先逐条显示；拥挤时同种标记合为更大的图标，点击查看次数与时间。")
                    .font(.caption).foregroundStyle(.secondary).frame(height: 32, alignment: .topLeading)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(names, id: \.self) { name in
                        HStack(spacing: 5) {
                            if let emoji = colors.emojis[name], !emoji.isEmpty { Text(emoji) }
                            else { Circle().fill(colors.color(name)).frame(width: 8, height: 8) }
                            Text(name).foregroundStyle(colors.color(name))
                        }.font(.caption)
                    }
                }
            }
            if data.isEmpty { Text("此范围没有标记；可以切换日期或标记。").font(.caption).foregroundStyle(.secondary) }
        }.padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            .onAppear { resetWindow() }
            .onChange(of: line) { _ in resetWindow() }
    }
}
