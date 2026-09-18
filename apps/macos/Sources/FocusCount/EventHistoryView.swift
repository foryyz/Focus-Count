import SwiftUI
import Charts
import FocusCountCore

struct EventHistoryView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var range = -1
    @State private var kind: String?
    @State private var search = ""
    @State private var page = 0
    @StateObject private var colors = MarkerColors()
    @State private var visibleKinds: Set<String> = []
    @State private var scatter = false
    @State private var selectedHour: Int?
    @State private var hoveredDate: Date?
    @State private var selectedBucket: Date?
    @State private var deleting: TimeEvent?
    @State private var purging: TimeEvent?
    private var source: [TimeEvent] { store.database.events ?? [] }
    private var scoped: [TimeEvent] {
        let start = EventAnalytics.periodStart(range: range)
        return EventAnalytics.records(source, days: nil).filter { start == nil || ($0.occurredAt >= start! && $0.occurredAt < chartTodayEnd) }
    }
    private var chartTodayEnd: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))! }
    private var allNames: [String] {
        var seen: Set<String> = []
        return source.sorted { $0.occurredAt == $1.occurredAt ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt < $1.occurredAt }
            .map { EventAnalytics.label($0.kind) }.filter { seen.insert($0).inserted }
    }
    private var shown: [String] { EventAnalytics.frequencies(scoped).map(\.id).filter { visibleKinds.contains($0) } }
    private func resetLines() { visibleKinds = Set(EventAnalytics.frequencies(scoped).prefix(5).map(\.id)); if let kind { visibleKinds.insert(kind) } }
    private var frequencies: [EventAnalytics.Frequency] {
        EventAnalytics.frequencies(scoped).filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) }
    }
    private var records: [TimeEvent] { scoped.filter { kind == nil || EventAnalytics.label($0.kind) == kind } }
    private var calendar: Calendar { .current }
    private var chartStart: Date {
        EventAnalytics.periodStart(range: range) ?? calendar.startOfDay(for: scoped.last?.occurredAt ?? Date())
    }
    private var chartEnd: Date {
        if range == -1 { return calendar.date(byAdding: .day, value: 7, to: chartStart)! }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(Date(), scoped.first?.occurredAt ?? Date())))!
    }
    private var weekDays: [Date] { (0..<7).map { calendar.date(byAdding: .day, value: $0, to: chartStart)! } }
    private func midpoint(_ date: Date) -> Date {
        guard range == -1 else { return date }
        let interval = calendar.dateInterval(of: .day, for: date)!
        return interval.start.addingTimeInterval(interval.duration / 2)
    }
    private func dateLabel(_ date: Date) -> String {
        range == -1 ? ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: date) - 1] : date.formatted(date: .abbreviated, time: .omitted)
    }
    private var maximumCount: Int { max(1, shown.flatMap { points($0) }.map(\.count).max() ?? 1) }
    private var countTicks: [Int] { Array(stride(from: 0, through: maximumCount, by: max(1, Int(ceil(Double(maximumCount) / 4))))) }
    private func hoverCount(_ name: String, at date: Date) -> String {
        if range == -1 && date >= chartTodayEnd { return "尚未到来" }
        return String(points(name).last(where: { $0.date <= date })?.count ?? 0) + " 次"
    }
    private var component: Calendar.Component {
        let days = calendar.dateComponents([.day], from: chartStart, to: chartEnd).day ?? 0
        return days > 730 ? .month : days > 90 ? .weekOfYear : .day
    }
    private var buckets: [EventAnalytics.Bucket] { EventAnalytics.buckets(records, component: component) }
    private var selection: DateInterval? { selectedBucket.flatMap { calendar.dateInterval(of: component, for: $0) } }
    private var timeline: [TimeEvent] {
        records.filter { event in (selection.map { event.occurredAt >= $0.start && event.occurredAt < $0.end } ?? true) && (selectedHour == nil || calendar.component(.hour, from: event.occurredAt) == selectedHour) }
    }
    private var grouped: [(day: Date, events: [TimeEvent])] {
        Dictionary(grouping: timeline, by: { calendar.startOfDay(for: $0.occurredAt) })
            .map { (day: $0.key, events: $0.value) }.sorted { $0.day > $1.day }
    }
    private var trash: [TimeEvent] { source.filter { $0.deletedAt != nil }.sorted { $0.occurredAt > $1.occurredAt } }
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Button { dismiss() } label: { Label("返回记录", systemImage: "arrow.left") }
                    .keyboardShortcut(.cancelAction)
                VStack(alignment: .leading, spacing: 4) {
                    Text("时间标记").font(.title2.weight(.semibold))
                    Text("看见生活里的重复与变化").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("页面", selection: $page) {
                    Text("概览").tag(0)
                    Text("时间轴").tag(1)
                    Text("最近删除").tag(2)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            if page == 2 { trashView }
            else {
                HStack(alignment: .top, spacing: 24) {
                    sidebar.frame(width: 200)
                    Divider()
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(kind ?? "全部标记").font(.title3.weight(.semibold)).lineLimit(1).help(kind ?? "全部标记")
                            Spacer()
                            Picker("日期", selection: $range) {
                                Text("本周").tag(-1)
                                Text("30 天").tag(30)
                                Text("90 天").tag(90)
                                Text("全部").tag(0)
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 280)
                        }
                        if page == 0 { overview }
                        else {
                            distribution
                            HStack {
                                Text(selectionTitle).font(.headline)
                                Spacer()
                                if selectedBucket != nil || selectedHour != nil {
                                    Button("清除明细筛选") { selectedBucket = nil; selectedHour = nil }.font(.caption)
                                }
                                Text("\(timeline.count) 次").font(.caption).foregroundStyle(.secondary)
                            }
                            timelineView.id(selectionTitle + (kind ?? "") + String(range))
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
        }.padding(24).frame(width: 1000, height: 700)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear { colors.ensure(allNames); resetLines() }
            .onChange(of: allNames) { _ in colors.ensure(allNames) }
            .onChange(of: range) { _ in selectedBucket = nil; selectedHour = nil; hoveredDate = nil; resetLines() }
            .onChange(of: kind) { _ in selectedBucket = nil; selectedHour = nil; if let kind { visibleKinds.insert(kind) } }
            .alert("删除这次时间标记？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("移至最近删除", role: .destructive) {
                    if let deleting { store.setEventDeleted(deleting.id, deleted: true) }
                    deleting = nil
                }
            }
            .alert("彻底删除这次时间标记？", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } })) {
                Button("取消", role: .cancel) { purging = nil }
                Button("彻底删除", role: .destructive) {
                    if let purging { store.purgeEvents([purging.id]) }
                    purging = nil
                }
            } message: { Text("无法在应用内恢复，旧文件导入也不会重新出现。已有独立备份不受影响。") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("查找标记", text: $search).textFieldStyle(.roundedBorder)
            Button { kind = nil; selectedBucket = nil } label: {
                HStack { Label("全部标记", systemImage: "square.stack"); Spacer(); Text("\(scoped.count)") }
                    .padding(10).background(kind == nil ? Color.teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(frequencies) { item in
                        HStack(spacing: 8) {
                            VStack(spacing: 6) {
                                ColorPicker("颜色", selection: Binding(get: { colors.color(item.id) }, set: { colors.set($0, for: item.id) }), supportsOpacity: false)
                                    .labelsHidden().help("调整 " + item.id + " 的颜色")
                                if page == 0 {
                                    Button {
                                        if visibleKinds.contains(item.id) { visibleKinds.remove(item.id) }
                                        else { visibleKinds.insert(item.id) }
                                    } label: { Image(systemName: visibleKinds.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(colors.color(item.id)) }
                                    .buttonStyle(.plain).help("显示或隐藏曲线").accessibilityLabel("显示或隐藏 " + item.id + " 曲线")
                                }
                            }
                            Button { kind = kind == item.id ? nil : item.id } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack { Text(item.id).fontWeight(.medium).lineLimit(1); Spacer(); Text("\(item.count) 次").foregroundStyle(.secondary) }
                                    Text(EventAnalytics.intervalText(item.weeksPerOccurrence)).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(item.id)
                        }.padding(10).background(kind == item.id ? colors.color(item.id).opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    if frequencies.isEmpty { Text("没有匹配的标记").font(.caption).foregroundStyle(.secondary).padding(.top) }
                }
            }
            Text("平均间隔 = 同种标记相邻两次的平均时间。按当前日期范围计算，至少需要两次。数值越小，越频繁。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("点击名称查看时段分布；点击色块调整颜色。颜色保存在这台 Mac，旧标记颜色不会因新标记加入而变化。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func points(_ name: String) -> [EventAnalytics.TrendPoint] {
        EventAnalytics.trend(scoped.filter { EventAnalytics.label($0.kind) == name }, start: chartStart, end: range == -1 ? chartTodayEnd : chartEnd, cumulative: false, component: component)
    }
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 28) {
                    metric("标记次数", "\(records.count) 次")
                    metric(kind == nil ? "标记种类" : "平均间隔", kind == nil ? "\(EventAnalytics.frequencies(scoped).count) 种" : EventAnalytics.intervalText(EventAnalytics.frequencies(records).first?.weeksPerOccurrence))
                    metric("最近一次", records.first?.occurredAt.formatted(date: .abbreviated, time: .omitted) ?? "—")
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("内容与次数").font(.headline)
                        Spacer()
                        Picker("曲线", selection: $scatter) {
                            Text("散点图").tag(true)
                            Text("频率变化").tag(false)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    }
                    Text(range == -1 ? "本周 · 周一至周日，统计截至今天" : chartStart.formatted(date: .abbreviated, time: .omitted) + " — " + chartEnd.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                    trendChart
                    if let date = hoveredDate {
                        Text(dateLabel(date) + "  ·  " + shown.map { name in
                            name + " " + hoverCount(name, at: date)
                        }.joined(separator: "    "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .topLeading)
                    } else {
                        Text(component == .day ? "每个点代表当天总次数，不累计；未来日期留空。" : component == .weekOfYear ? "每个点代表当周总次数；首尾周可能不完整。" : "每个点代表当月总次数；首尾月可能不完整。")
                            .font(.caption).foregroundStyle(.secondary).frame(height: 30, alignment: .topLeading)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(shown, id: \.self) { name in
                            Button { kind = kind == name ? nil : name } label: {
                                HStack(spacing: 6) { Capsule().fill(colors.color(name)).frame(width: 18, height: 3); Text(name).lineLimit(1) }
                            }.buttonStyle(.plain).font(.caption).help(name)
                        }
                    }
                    Text("默认显示次数最多的 5 种，左侧勾选可调整。").font(.caption2).foregroundStyle(.secondary)
                }.padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                heatmap
            }.padding(.trailing, 6)
        }
    }
    private var trendChart: some View {
        Chart {
            if range == -1 {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, date in
                    RectangleMark(xStart: .value("区间开始", date), xEnd: .value("区间结束", calendar.date(byAdding: .day, value: 1, to: date)!), yStart: .value("底部", 0), yEnd: .value("顶部", maximumCount))
                        .foregroundStyle(Color.teal.opacity(index % 2 == 0 ? 0.07 : 0.025))
                        .accessibilityHidden(true)
                }
            }
            ForEach(shown, id: \.self) { name in
                ForEach(points(name)) { point in
                    if !scatter {
                        LineMark(x: .value("日期", midpoint(point.date)), y: .value("次数", point.count), series: .value("标记", name))
                            .foregroundStyle(by: .value("标记", name))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: kind == name ? 3 : 2))
                            .opacity(kind == nil || kind == name ? 1 : 0.25)
                    }
                    PointMark(x: .value("日期", midpoint(point.date)), y: .value("次数", point.count))
                        .foregroundStyle(by: .value("标记", name))
                        .symbol(by: .value("标记", name))
                        .symbolSize(scatter ? 65 : 30)
                        .opacity(kind == nil || kind == name ? 1 : 0.25)
                        .accessibilityLabel(name + " " + dateLabel(point.date))
                        .accessibilityValue("\(point.count) 次")
                }
            }
            if let date = hoveredDate { RuleMark(x: .value("查看", date)).foregroundStyle(Color.secondary.opacity(0.3)).lineStyle(StrokeStyle(dash: [3, 3])) }
        }
        .chartForegroundStyleScale(domain: shown, range: shown.map { colors.color($0) })
        .chartLegend(.hidden)
        .chartXScale(domain: chartStart...chartEnd)
        .chartYScale(domain: 0...maximumCount)
        .chartXAxis { markerDateAxis }
        .chartPlotStyle { plot in plot.overlay(Rectangle().stroke(Color.secondary.opacity(0.25), lineWidth: 1)) }
        .chartYAxis { AxisMarks(values: countTicks) { value in
            if let number = value.as(Int.self) { AxisGridLine(); AxisValueLabel { Text("\(number)") } }
        } }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let plot = geometry[proxy.plotAreaFrame]
                        hoveredDate = plot.contains(location) ? proxy.value(atX: location.x - plot.minX, as: Date.self) : nil
                    case .ended: hoveredDate = nil
                    }
                }
            }
        }.frame(height: 160)
        .overlay { if shown.isEmpty { Text("在左侧勾选要比较的标记").font(.caption).foregroundStyle(.secondary) } }
    }
    @AxisContentBuilder private var markerDateAxis: some AxisContent {
        if range == -1 {
            AxisMarks(values: weekDays) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.secondary.opacity(0.25)) }
            AxisMarks(values: weekDays.map { midpoint($0) }) { value in
                AxisTick(length: 5)
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(dateLabel(date)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary) }
                }
            }
        } else {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.secondary.opacity(0.22))
                AxisTick(length: 6)
                AxisValueLabel()
            }
        }
    }
    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("一天中的时间分布").font(.headline); Spacer(); if let kind { Text(kind).foregroundStyle(colors.color(kind)) } }
            if let kind {
                let counts = EventAnalytics.hours(records)
                let maximum = max(1, counts.max() ?? 1)
                HStack(spacing: 3) {
                    ForEach(0..<24, id: \.self) { hour in
                        Button {
                            selectedHour = hour; selectedBucket = nil; page = 1
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(counts[hour] == 0 ? Color.primary.opacity(0.05) : colors.color(kind).opacity(0.2 + 0.8 * Double(counts[hour]) / Double(maximum)))
                                .frame(height: 34)
                        }.buttonStyle(.plain)
                            .help(String(format: "%02d:00–%02d:00 · %d 次 · %.0f%%", hour, hour + 1, counts[hour], records.isEmpty ? 0 : Double(counts[hour]) / Double(records.count) * 100))
                            .accessibilityLabel("\(hour) 至 \(hour + 1) 点，\(counts[hour]) 次，查看明细")
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { index in Text(String(format: "%02d", index * 3)).frame(maxWidth: .infinity, alignment: .leading) }
                    Text("24")
                }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                HStack {
                    Text(records.count < 3 ? "目前仅 \(records.count) 次记录，暂不推断时段习惯。" : "按本地时间统计 · 点击时段查看明细")
                    Spacer()
                    Text("少")
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { opacity in RoundedRectangle(cornerRadius: 2).fill(colors.color(kind).opacity(opacity)).frame(width: 12, height: 10) }
                    Text("多")
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                Text("在左侧选择一种标记，查看它通常发生在几点。").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 24)
            }
        }.padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
    private var distribution: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(component == .day ? "每日分布" : component == .weekOfYear ? "每周分布" : "每月分布").font(.subheadline.weight(.medium))
                Spacer()
                Text("点击柱形查看时间轴").font(.caption).foregroundStyle(.secondary)
            }
            Chart(buckets) { bucket in
                RectangleMark(xStart: .value("开始", bucket.interval.start), xEnd: .value("结束", bucket.interval.end), yStart: .value("基线", 0), yEnd: .value("次数", bucket.count))
                    .foregroundStyle(selectedBucket == nil || selectedBucket == bucket.id ? Color.teal : Color.teal.opacity(0.25))
                    .cornerRadius(3)
                    .accessibilityLabel(bucket.interval.start.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(bucket.count) 次")
            }
            .chartXScale(domain: chartStart...chartEnd)
            .chartXAxis { markerDateAxis }
            .chartYScale(domain: 0...max(1, buckets.map(\.count).max() ?? 1))
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if let number = value.as(Int.self) { AxisGridLine(); AxisValueLabel { Text("\(number)") } }
            } }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let plot = geometry[proxy.plotAreaFrame]
                            guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX) else { return }
                            let start = calendar.dateInterval(of: component, for: date)!.start
                            selectedHour = nil
                            selectedBucket = selectedBucket == start ? nil : start
                        }
                }
            }.frame(height: 120)
            .overlay { if records.isEmpty { Text("此范围内暂无标记").font(.caption).foregroundStyle(.secondary) } }
        }.padding(14).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
    private var selectionTitle: String {
        if let selectedHour { return String(format: "%02d:00–%02d:00 · 最新在前", selectedHour, selectedHour + 1) }
        guard let selection else { return "时间轴 · 最新在前" }
        if component == .day { return selection.start.formatted(date: .abbreviated, time: .omitted) }
        return selection.start.formatted(date: .abbreviated, time: .omitted) + " — " + selection.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
    }
    private var timelineView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if grouped.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").font(.title).foregroundStyle(.teal)
                        Text("这里还没有标记").font(.headline)
                        Text("可切换日期范围，或回到计时页输入 !文字添加。").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 28)
                }
                ForEach(grouped, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.day.formatted(.dateTime.year().month().day().weekday())).font(.subheadline.weight(.semibold))
                            Text("\(group.events.count) 次").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(group.events) { event in
                            HStack(spacing: 12) {
                                Text(event.occurredAt.formatted(date: .omitted, time: .standard))
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 78, alignment: .trailing)
                                Circle().fill(colors.color(EventAnalytics.label(event.kind))).frame(width: 6, height: 6)
                                Text(EventAnalytics.label(event.kind)).font(.body).textSelection(.enabled)
                                Spacer()
                                Button { deleting = event } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                                    .buttonStyle(.borderless).help("删除这次标记").accessibilityLabel("删除 " + event.kind).disabled(store.blocked)
                            }.padding(.vertical, 7)
                        }
                    }
                }
            }.padding(.trailing, 8)
        }
    }
    private var trashView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(trash.count) 次已删除标记 · 不参与时间轴和频率统计").font(.subheadline).foregroundStyle(.secondary)
            if trash.isEmpty { Text("最近删除为空").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                List(trash) { event in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.kind).font(.headline)
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复") { store.setEventDeleted(event.id, deleted: false) }
                        Button("彻底删除", role: .destructive) { purging = event }
                    }.padding(.vertical, 5).disabled(store.blocked)
                }
            }
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded))
        }
    }
}
