import SwiftUI
import Charts
import FocusCountCore

struct PhoneFocusAnalysis: View {
    @ObservedObject var store: PhoneStore
    @ObservedObject var appearance: FocusAppearanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var period = FocusAnalysisData.Period.week
    @State private var category = "all"
    @State private var activity = ""
    @State private var page = 0
    @State private var bars = false
    @State private var shareMode = 0
    @State private var byCategory = false
    @State private var managing = false
    @State private var selected: Date?
    @State private var average = false
    @State private var editing: StudySession?
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var customEnd = Date()
    private var interval: DateInterval {
        if period == .custom {
            let calendar = Calendar.current
            return DateInterval(start: calendar.startOfDay(for: min(customStart, customEnd)), end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStart, customEnd)))!)
        }
        return FocusAnalysisData.interval(period, records: store.sessions)
    }
    private var records: [StudySession] {
        FocusAnalysisData.filtered(store.sessions, interval: interval).filter {
            (activity.isEmpty || $0.subject == activity) && (category == "all" || appearance.categoryKey($0.subject) == category)
        }
    }
    private var buckets: [FocusBucket] { FocusAnalysisData.buckets(records, interval: interval) }
    private var averages: [Date: Double] {
        FocusAnalysisData.trailingWeekAverage(store.sessions.filter {
            (activity.isEmpty || $0.subject == activity) && (category == "all" || appearance.categoryKey($0.subject) == category)
        }, days: buckets.map(\.start))
    }
    private var items: [FocusBreakdown] { FocusAnalysisData.breakdown(records) { byCategory ? appearance.category($0.subject) : $0.subject } }
    private func color(_ item: FocusBreakdown) -> Color {
        appearance.color(byCategory ? item.records.first.map { appearance.categoryKey($0.subject) } ?? "category:none" : "activity:" + item.name)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Picker("周期", selection: $period) { ForEach(FocusAnalysisData.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        Spacer()
                        Menu {
                            Picker("分类", selection: $category) {
                                Text("全部分类").tag("all"); Text("未分类").tag("category:none")
                                ForEach(appearance.settings.categories) { Text($0.name).tag("category:" + $0.id.uuidString) }
                            }
                            Picker("活动", selection: $activity) { Text("全部活动").tag(""); ForEach(store.subjects, id: \.self) { Text($0).tag($0) } }
                            Button("重置筛选") { category = "all"; activity = "" }
                        } label: { Label(category == "all" && activity.isEmpty ? "筛选" : "已筛选", systemImage: "line.3.horizontal.decrease") }
                    }
                    if period == .custom {
                        DatePicker("开始", selection: $customStart, displayedComponents: .date)
                        DatePicker("结束", selection: $customEnd, displayedComponents: .date)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(phoneDuration(records.reduce(0) { $0 + $1.activeSeconds })).font(.system(.largeTitle, design: .rounded, weight: .medium)).monospacedDigit()
                        Text("\(records.count) 次专注 · \(Set(records.map(\.subject)).count) 个活动").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("分析内容", selection: $page) { Text("投入趋势").tag(0); Text("时间去向").tag(1) }.pickerStyle(.segmented)
                    if page == 0 { trend } else { distribution }
                    if records.isEmpty { ContentUnavailableView("暂无专注记录", systemImage: "chart.bar.xaxis", description: Text("试试其他周期或筛选条件。")) }
                    Text("按开始日期统计已保存时长，跨午夜整段归入开始日。").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("专注分析").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button { managing = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("分类与颜色") }
                }
                .sheet(item: $editing) { RecordEditor(store: store, session: $0) {} }
                .sheet(isPresented: $managing) { PhoneFocusAppearance(appearance: appearance, activities: store.subjects) }
                .onAppear { appearance.ensureColors(store.subjects) }
                .onChange(of: period) { _, _ in selected = nil }
                .onChange(of: category) { _, _ in selected = nil }
                .onChange(of: activity) { _, _ in selected = nil }
        }
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("按\(FocusAnalysisData.grain(interval).rawValue)汇总").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("趋势图形", selection: $bars) { Text("折线").tag(false); Text("条形").tag(true) }.pickerStyle(.segmented).frame(width: 160)
            }
            if FocusAnalysisData.grain(interval) == .day && buckets.count > 7 {
                Toggle("7 日平均", isOn: $average).font(.caption)
            }
            Chart(buckets) { bucket in
                if bars {
                    BarMark(x: .value("日期", bucket.start), y: .value("小时", bucket.seconds / 3600)).foregroundStyle(Color.teal.gradient).cornerRadius(3)
                } else {
                    AreaMark(x: .value("日期", bucket.start), y: .value("小时", bucket.seconds / 3600)).foregroundStyle(LinearGradient(colors: [.teal.opacity(0.22), .teal.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("日期", bucket.start), y: .value("小时", bucket.seconds / 3600)).foregroundStyle(.teal)
                    if buckets.count <= 7 { PointMark(x: .value("日期", bucket.start), y: .value("小时", bucket.seconds / 3600)).foregroundStyle(.teal) }
                }
                if average && FocusAnalysisData.grain(interval) == .day && buckets.count > 7 {
                    LineMark(x: .value("日期", bucket.start), y: .value("小时", (averages[bucket.start] ?? 0) / 3600), series: .value("序列", "7 日平均"))
                        .foregroundStyle(Color.teal.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }.chartXScale(domain: interval.start...interval.end).chartYAxisLabel("小时")
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisGridLine(); AxisValueLabel(format: period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.month().day()) } }
                .chartXSelection(value: $selected).frame(height: 240)
            if let selected, let bucket = buckets.first(where: { selected >= $0.start && selected < $0.end }) {
                Text(bucket.start.formatted(date: .abbreviated, time: .omitted) + " · " + phoneDuration(bucket.seconds)).font(.subheadline)
                ForEach(bucket.records.sorted { $0.startedAt > $1.startedAt }) { record in
                    Button { editing = record } label: {
                        HStack { Text(record.subject); Spacer(); Text(phoneDuration(record.activeSeconds)).foregroundStyle(.secondary) }.font(.caption).frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityHint("编辑专注记录")
                }
            } else { Text("轻点或按住图表查看时长及记录。").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var distribution: some View {
        VStack(spacing: 16) {
            Picker("分组", selection: $byCategory) { Text("按活动").tag(false); Text("按分类").tag(true) }.pickerStyle(.segmented)
            Picker("分布图形", selection: $shareMode) { Text("条形").tag(0); Text("环形").tag(1); Text("扇形").tag(2) }.pickerStyle(.segmented)
            if shareMode != 0 { FocusShareChart(items: items, activityCount: Set(records.map(\.subject)).count, pie: shareMode == 2, color: color).frame(height: 290) }
            ForEach(items) { item in
                VStack(spacing: 7) {
                    HStack {
                        Circle().fill(color(item)).frame(width: 8, height: 8)
                        Text(item.name)
                        Spacer()
                        Text(phoneDuration(item.seconds)).monospacedDigit()
                    }.font(.subheadline)
                    if shareMode == 0 { ProgressView(value: item.seconds, total: max(1, items.first?.seconds ?? 1)).tint(color(item)) }
                }.padding(.vertical, 3)
            }
        }
    }
}

struct PhoneFocusAppearance: View {
    @ObservedObject var appearance: FocusAppearanceStore
    let activities: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var renamed = ""
    @State private var renaming: FocusCategory?
    @State private var removing: FocusCategory?
    var body: some View {
        NavigationStack {
            Form {
                if let error = appearance.error { Text(error).foregroundStyle(.red) }
                Section("分类") {
                    HStack { TextField("新分类", text: $name); Button("添加") { if appearance.addCategory(name) { name = ""; appearance.ensureColors(activities) } } }
                    ForEach(appearance.settings.categories) { category in
                        HStack {
                            ColorPicker(category.name, selection: Binding(get: { appearance.color("category:" + category.id.uuidString) }, set: { appearance.setColor($0, key: "category:" + category.id.uuidString) }), supportsOpacity: false)
                            Menu {
                                Button("重命名") { renamed = category.name; renaming = category }
                                Button("删除分类", role: .destructive) { removing = category }
                            } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("管理分类")
                        }
                    }
                }
                Section {
                    ForEach(activities, id: \.self) { activity in
                        VStack(alignment: .leading) {
                            ColorPicker(activity, selection: Binding(get: { appearance.color("activity:" + activity) }, set: { appearance.setColor($0, key: "activity:" + activity) }), supportsOpacity: false)
                            Picker("分类", selection: Binding(get: { appearance.categoryID(activity) }, set: { appearance.assign(activity, to: $0) })) {
                                Text("未分类").tag(Optional<UUID>.none)
                                ForEach(appearance.settings.categories) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                    }
                } header: { Text("活动") } footer: { Text("分类与颜色应用于本机全部历史记录，暂不随 JSON 同步。") }
            }.navigationTitle("分类与颜色").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .alert("重命名分类", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                    TextField("名称", text: $renamed)
                    Button("取消", role: .cancel) { renaming = nil }
                    Button("保存") { if let renaming { appearance.rename(renaming.id, to: renamed) }; renaming = nil }
                }
                .confirmationDialog("删除分类后活动变为未分类，记录保留。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                    Button("删除分类", role: .destructive) { if let removing { appearance.remove(removing.id) }; removing = nil }
                }
        }
    }
}
