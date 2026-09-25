import SwiftUI
import Charts
import FocusCountCore

struct FocusAnalysisView: View {
    @ObservedObject var store: StudyStore
    @StateObject private var appearance = FocusAppearanceStore()
    @State private var period = FocusAnalysisData.Period.week
    @State private var category = "all"
    @State private var activity = ""
    @State private var byCategory = false
    @State private var customStart = Calendar.current.startOfDay(for: Date())
    @State private var customEnd = Date()
    @State private var zoom: DateInterval?
    @State private var selected: Date?
    @State private var managing = false
    @State private var editing: StudySession?
    private var activities: [String] { Array(Set(store.database.sessions.map(\.subject))).sorted() }
    private var interval: DateInterval {
        if period == .custom {
            let start = Calendar.current.startOfDay(for: min(customStart, customEnd))
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(customStart, customEnd)))!
            return DateInterval(start: start, end: end)
        }
        return FocusAnalysisData.interval(period, records: store.database.sessions)
    }
    private var records: [StudySession] {
        FocusAnalysisData.filtered(store.database.sessions, interval: interval).filter {
            (activity.isEmpty || $0.subject == activity) &&
            (category == "all" || (appearance.categoryID($0.subject)?.uuidString ?? "none") == category)
        }
    }
    private var plotInterval: DateInterval {
        if let zoom { return zoom }
        if period == .week { return DateInterval(start: interval.start, end: Calendar.current.date(byAdding: .day, value: 7, to: interval.start)!) }
        return interval
    }
    private var buckets: [FocusBucket] { FocusAnalysisData.buckets(records, interval: plotInterval) }
    private var total: Double { records.reduce(0) { $0 + $1.activeSeconds } }
    private var breakdown: [FocusBreakdown] { FocusAnalysisData.breakdown(records) { byCategory ? appearance.category($0.subject) : $0.subject } }
    private var selectedBucket: FocusBucket? { buckets.first { $0.start == selected } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            metrics
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 18) {
                    trend.frame(maxWidth: .infinity, maxHeight: .infinity)
                    distribution.frame(width: min(360, max(280, geometry.size.width * 0.3)), height: geometry.size.height)
                }
            }.frame(minHeight: selected == nil ? 300 : 150)
            if let bucket = selectedBucket { details(bucket) }
            if let error = appearance.error ?? store.error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("按记录开始日期统计有效时长，暂停不计入；跨午夜记录归于开始日。日均包含所选周期内无记录的日期，最近删除不参与统计。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 912, minHeight: 552)
            .background(Color(nsColor: .windowBackgroundColor))
            .sheet(isPresented: $managing) { FocusCategoryEditor(appearance: appearance, activities: activities) }
            .sheet(item: $editing) { SessionEditor(store: store, session: $0) }
            .onAppear { appearance.ensureColors(activities) }
            .onChange(of: activities) { appearance.ensureColors($0) }
            .onChange(of: period) { _ in clearSelection() }
            .onChange(of: customStart) { _ in clearSelection() }
            .onChange(of: customEnd) { _ in clearSelection() }
            .onChange(of: appearance.settings.categories) { values in
                if category != "all" && category != "none" && !values.contains(where: { $0.id.uuidString == category }) { category = "all" }
            }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("专注分析").font(.title2.bold())
                    Text("看见每天的投入，也看见时间的去向").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { managing = true } label: { Label("分类与颜色", systemImage: "folder.badge.gearshape") }
            }
            HStack(spacing: 12) {
                Picker("周期", selection: $period) { ForEach(FocusAnalysisData.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 460)
                Spacer()
                Picker("分类", selection: $category) {
                    Text("全部分类").tag("all"); Text("未分类").tag("none")
                    ForEach(appearance.settings.categories) { Text($0.name).tag($0.id.uuidString) }
                }.frame(width: 170)
                Picker("活动", selection: $activity) {
                    Text("全部活动").tag("")
                    ForEach(activities, id: \.self) { Text($0).tag($0) }
                }.frame(width: 180)
            }
            if period == .custom {
                HStack {
                    DatePicker("从", selection: $customStart, in: ...Date(), displayedComponents: .date)
                    DatePicker("至", selection: $customEnd, in: ...Date(), displayedComponents: .date)
                    if customStart > customEnd { Text("已按较早日期至较晚日期统计").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }.fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var metrics: some View {
        HStack(spacing: 36) {
            metric("有效专注时长", duration(total))
            metric("日均时长", duration(total / Double(FocusAnalysisData.dayCount(interval))))
            metric("专注次数", "\(records.count) 次")
            metric("有专注的天数", "\(Set(records.map { Calendar.current.startOfDay(for: $0.startedAt) }).count) 天")
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(interval.start.formatted(.dateTime.year().month().day()) + " — " + interval.end.addingTimeInterval(-1).formatted(.dateTime.month().day()))
                Text("\(FocusAnalysisData.dayCount(interval)) 天 · 筛选周期")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }
    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit() }
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("投入趋势").font(.headline)
                Text("按\(FocusAnalysisData.grain(plotInterval).rawValue)汇总").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if zoom != nil { Button("查看全貌") { clearSelection() } }
            }
            GeometryReader { chartGeometry in
            Chart {
                ForEach(buckets) { bucket in
                    if bucket.records.isEmpty {
                        BarMark(x: .value("日期", midpoint(bucket)), y: .value("小时", 0), width: .fixed(barWidth(chartGeometry.size.width))).foregroundStyle(.clear)
                    } else {
                        ForEach(FocusAnalysisData.breakdown(bucket.records, key: { byCategory ? appearance.category($0.subject) : $0.subject }).sorted { $0.name < $1.name }) { item in
                            BarMark(x: .value("日期", midpoint(bucket)), y: .value("小时", item.seconds / 3600), width: .fixed(barWidth(chartGeometry.size.width)))
                                .foregroundStyle(itemColor(item)).cornerRadius(2)
                                .accessibilityLabel("\(bucket.start.formatted(date: .abbreviated, time: .omitted))，\(item.name)，\(duration(item.seconds))")
                        }
                    }
                }
                if let bucket = selectedBucket { RuleMark(x: .value("所选日期", midpoint(bucket))).foregroundStyle(Color.primary.opacity(0.25)).lineStyle(StrokeStyle(dash: [3, 3])) }
            }
            .chartXScale(domain: plotInterval.start...plotInterval.end)
            .chartYScale(domain: 0...max(1, (buckets.map(\.seconds).max() ?? 0) / 3600 * 1.1))
            .chartYAxisLabel("有效时长（小时）")
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date)).font(.caption2)
                                .foregroundStyle(date > Date() ? Color.secondary.opacity(0.5) : Color.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                            let plot = geometry[proxy.plotAreaFrame]
                            guard plot.contains(gesture.location), let date: Date = proxy.value(atX: gesture.location.x - plot.minX) else { return }
                            selected = buckets.first { date >= $0.start && date < $0.end }?.start
                        })
                }
            }
            }
            if records.isEmpty { Text("这个周期暂无符合条件的专注记录，可调整周期或筛选。").font(.callout).foregroundStyle(.secondary) }
            Text("点击日期查看明细 · 颜色对应右侧\(byCategory ? "分类" : "活动") · 本周未来日期留空")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
    private var distribution: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("时间去向").font(.headline); Spacer() }
            Picker("分布", selection: $byCategory) { Text("按分类").tag(true); Text("按活动").tag(false) }.pickerStyle(.segmented)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(breakdown) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle().fill(itemColor(item)).frame(width: 8, height: 8)
                                Text(item.name).lineLimit(1).help(item.name)
                                Spacer()
                                Text(total > 0 ? String(format: "%.0f%%", item.seconds / total * 100) : "0%")
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                            GeometryReader { geometry in
                                Capsule().fill(itemColor(item).opacity(0.12))
                                Capsule().fill(itemColor(item)).frame(width: total > 0 ? max(0, geometry.size.width * item.seconds / total) : 0)
                            }.frame(height: 7)
                            HStack { Text(duration(item.seconds)); Spacer(); Text("\(item.records.count) 次") }.font(.caption).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }
                    if breakdown.isEmpty { Text("暂无数据").foregroundStyle(.secondary) }
                }.padding(.vertical, 4)
            }
            if byCategory && appearance.settings.categories.isEmpty {
                Button("将活动分为学习、娱乐等分类") { managing = true }.font(.caption)
            }
        }.padding(18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
    private func details(_ bucket: FocusBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(bucket.start.formatted(date: .abbreviated, time: .omitted) + (FocusAnalysisData.dayCount(DateInterval(start: bucket.start, end: bucket.end)) > 1 ? " — " + bucket.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted) : "")).font(.headline)
                Text("\(duration(bucket.seconds)) · \(bucket.records.count) 次").foregroundStyle(.secondary)
                Spacer()
                if FocusAnalysisData.dayCount(DateInterval(start: bucket.start, end: bucket.end)) > 1 {
                    Button("放大这段时间") { zoom = DateInterval(start: bucket.start, end: bucket.end); selected = nil }
                }
                Button { selected = nil } label: { Image(systemName: "xmark") }.help("收起明细")
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(bucket.records.sorted { $0.startedAt > $1.startedAt }) { record in
                        HStack {
                            Circle().fill(appearance.color("activity:" + record.subject)).frame(width: 8, height: 8)
                            Text(record.subject).lineLimit(1)
                            Text(appearance.category(record.subject)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                            Text(duration(record.activeSeconds)).monospacedDigit()
                            Text(record.focus).frame(width: 20)
                            Button("编辑") { editing = record }.disabled(store.blocked)
                        }.font(.callout)
                    }
                    if bucket.records.isEmpty { Text(bucket.start > Date() ? "尚未到来的日期" : "这段时间没有专注记录").foregroundStyle(.secondary) }
                }
            }.frame(height: 100)
        }.padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
    private func barWidth(_ width: Double) -> Double { max(2, min(64, (width - 40) / Double(max(1, buckets.count)) * 0.62)) }
    private func midpoint(_ bucket: FocusBucket) -> Date { bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2) }
    private var axisDates: [Date] {
        let values = buckets.map(midpoint)
        let stride = max(1, Int(ceil(Double(values.count) / 8)))
        return values.enumerated().filter { $0.offset % stride == 0 || $0.offset == values.count - 1 }.map(\.element)
    }
    private func axisLabel(_ midpoint: Date) -> String {
        let date = buckets.first { midpoint >= $0.start && midpoint < $0.end }?.start ?? midpoint
        if period == .week && zoom == nil { return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: date) - 1] }
        return FocusAnalysisData.grain(plotInterval) == .month ? date.formatted(.dateTime.year().month()) : date.formatted(.dateTime.month().day())
    }
    private func itemColor(_ item: FocusBreakdown) -> Color {
        appearance.color(byCategory ? appearance.categoryKey(item.records.first?.subject ?? "") : "activity:" + item.name)
    }
    private func clearSelection() { zoom = nil; selected = nil }
}
