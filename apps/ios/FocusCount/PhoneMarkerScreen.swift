import SwiftUI
import FocusCountCore

struct PhoneEventHistory: View {
    @ObservedObject var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var colors = MarkerColors()
    @State private var mode = 0
    @State private var page = 0
    @State private var range = -1
    @State private var kind = ""
    @State private var command = ""
    @State private var search = ""
    @State private var style = false
    @State private var expanded = false
    @State private var adding = false
    @State private var pendingEdit: TimeEvent?
    @State private var pendingDelete: TimeEvent?
    @State private var pendingStyle = false
    @State private var editing: TimeEvent?
    @State private var deleting: TimeEvent?
    @State private var purging: Set<UUID> = []
    private let calendar = Calendar.current
    private var source: [TimeEvent] { store.state.events ?? [] }
    private var active: [TimeEvent] { EventAnalytics.records(source, days: nil).filter { $0.occurredAt < end } }
    private var names: [String] { Array(Set(source.map { EventAnalytics.label($0.kind) })).sorted() }
    private var end: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))! }
    private var start: Date { EventAnalytics.periodStart(range: range) ?? calendar.startOfDay(for: active.last?.occurredAt ?? Date()) }
    private var records: [TimeEvent] { active.filter { $0.occurredAt >= start && (kind.isEmpty || EventAnalytics.label($0.kind) == kind) } }
    private var trash: [TimeEvent] { source.filter { $0.deletedAt != nil }.sorted { $0.occurredAt > $1.occurredAt } }
    private var timeline: [TimeEvent] { (page == 2 ? trash : records).filter { search.isEmpty || $0.kind.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("页面", selection: $page) {
                        Text("可视化").tag(0); Text("时间轴").tag(1); Text("最近删除").tag(2)
                    }.pickerStyle(.segmented)
                    if page != 2 {
                        filters
                        if !kind.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(records.count) 次 · " + EventAnalytics.weeklyText(EventAnalytics.weeklyRate(count: records.count, start: start))).font(.headline)
                                Text("最近一次：" + (records.first?.occurredAt.formatted(date: .abbreviated, time: .shortened) ?? "—")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if page == 0 {
                        HStack {
                            Text("看见重复与变化").font(.headline)
                            Spacer()
                            Button { expanded = true } label: { Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right") }.font(.subheadline)
                        }
                        charts().frame(height: 530)
                        Text("平均每周次数按整个所选周期计算，包含无记录日期；本周按周一至今天计算。颜色与 emoji 保存在本机，暂不随 JSON 交换。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        if page == 1 && !kind.isEmpty { hourDistribution }
                        TextField("查找标记", text: $search).textFieldStyle(.roundedBorder)
                        if page == 2 {
                            Button("清空最近删除", role: .destructive) { purging = Set(trash.map(\.id)) }.disabled(trash.isEmpty || store.blocked)
                        }
                        if timeline.isEmpty { ContentUnavailableView("暂无标记", systemImage: "mappin.circle", description: Text("可调整日期范围，或添加新的标记。")) }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(timeline) { event in
                                recordRow(event)
                                Divider().padding(.vertical, 12)
                            }
                        }
                    }
                    if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding()
            }
            .navigationTitle("时间标记").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加标记").disabled(store.blocked) }
            }
            .sheet(isPresented: $adding) { addSheet }
            .sheet(isPresented: $style) { styleSheet }
            .sheet(item: $editing) { PhoneMarkerEditor(store: store, event: $0) }
            .fullScreenCover(isPresented: $expanded, onDismiss: {
                if let event = pendingEdit { pendingEdit = nil; editing = event }
                if let event = pendingDelete { pendingDelete = nil; deleting = event }
                if pendingStyle { pendingStyle = false; style = true }
            }) {
                NavigationStack {
                    GeometryReader { geometry in
                        VStack(spacing: 8) {
                            if geometry.size.height < 500 {
                                HStack {
                                    Picker("周期", selection: $range) { Text("本周").tag(-1); Text("30 天").tag(30); Text("全部").tag(0) }.pickerStyle(.segmented).frame(maxWidth: 300)
                                    Picker("标记", selection: $kind) { Text("全部标记").tag(""); ForEach(names, id: \.self) { Text($0).tag($0) } }.labelsHidden()
                                }
                            } else { filters }
                            charts(compact: geometry.size.height < 500).frame(maxHeight: .infinity)
                        }.padding(.horizontal).padding(.bottom, 6)
                    }.navigationTitle("标记可视化").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { expanded = false } } }
                }
            }
            .alert("删除这次时间标记？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("移至最近删除", role: .destructive) {
                    if let deleting { store.setEventDeleted(deleting.id, deleted: true) }; deleting = nil
                }
            }
            .alert("彻底删除这 \(purging.count) 次标记？", isPresented: Binding(get: { !purging.isEmpty }, set: { if !$0 { purging = [] } })) {
                Button("取消", role: .cancel) { purging = [] }
                Button("彻底删除", role: .destructive) { store.purgeEvents(purging); purging = [] }
            } message: { Text("无法在应用内恢复，导入旧文件不会重新出现。已有备份不受影响。") }
            .onAppear { colors.ensure(names) }
            .onChange(of: names) { _, value in colors.ensure(value) }
        }
    }
    private var filters: some View {
        VStack(spacing: 8) {
            Picker("周期", selection: $range) { Text("本周").tag(-1); Text("30 天").tag(30); Text("全部").tag(0) }.pickerStyle(.segmented)
            HStack {
                Picker("标记", selection: $kind) {
                    Text("全部标记").tag("")
                    ForEach(names, id: \.self) { name in Text((colors.emojis[name] ?? "") + " " + name).tag(name) }
                }.labelsHidden()
                Spacer()
                if !kind.isEmpty { Button { if expanded { pendingStyle = true; expanded = false } else { style = true } } label: { Image(systemName: "paintpalette") }.accessibilityLabel("设置颜色与 emoji") }
                Text("\(records.count) 次").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func charts(compact: Bool = false) -> some View {
        PhoneMarkerCharts(mode: $mode, events: records, start: start, end: end, isWeek: range == -1, colors: colors, edit: { event in
            if expanded { pendingEdit = event; expanded = false } else { editing = event }
        }, delete: { event in
            if expanded { pendingDelete = event; expanded = false } else { deleting = event }
        }, compact: compact).id(range)
    }
    private var hourDistribution: some View {
        let hours = EventAnalytics.hours(records)
        let peak = max(1, hours.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("一天中的时间分布").font(.headline)
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 3).fill(colors.color(kind).opacity(hours[hour] == 0 ? 0.06 : 0.2 + Double(hours[hour]) / Double(peak) * 0.8))
                        .frame(height: 28).accessibilityLabel("\(hour) 点，\(hours[hour]) 次")
                }
            }
            HStack { Text("00:00"); Spacer(); Text("12:00"); Spacer(); Text("24:00") }.font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func recordRow(_ event: TimeEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(event.kind).font(.headline)
            } icon: { Text(colors.emojis[EventAnalytics.label(event.kind)] ?? "●").foregroundStyle(colors.color(EventAnalytics.label(event.kind))) }
            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard)).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                if page == 2 {
                    Button("恢复") { store.setEventDeleted(event.id, deleted: false) }
                    Spacer()
                    Button("彻底删除", role: .destructive) { purging = [event.id] }
                } else {
                    Button("编辑") { editing = event }
                    Spacer()
                    Button("删除", role: .destructive) { deleting = event }
                }
            }.frame(minHeight: 44).disabled(store.blocked)
        }
    }
    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField("!文字，例如 !冥想", text: $command).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("只记录当前时间，不影响正在进行的专注。").font(.footnote).foregroundStyle(.secondary)
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("添加标记").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.markCommand(command) { command = ""; adding = false } }.disabled(store.blocked || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.presentationDetents([.medium, .large])
    }
    private var styleSheet: some View {
        NavigationStack {
            Form {
                Text(kind).font(.headline)
                TextField("Emoji（留空使用颜色）", text: Binding(get: { colors.emojis[kind] ?? "" }, set: { colors.setEmoji($0, for: kind) }))
                ColorPicker("标记颜色", selection: Binding(get: { colors.color(kind) }, set: { colors.set($0, for: kind) }), supportsOpacity: false)
                Text("颜色与 emoji 将应用于这种标记的全部历史记录，仅保存在当前设备。").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("标记外观").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { style = false } } }
        }.presentationDetents([.medium, .large])
    }
}

private struct PhoneMarkerCharts: View {
    @Binding var mode: Int
    let events: [TimeEvent]
    let start: Date
    let end: Date
    let isWeek: Bool
    @ObservedObject var colors: MarkerColors
    let edit: (TimeEvent) -> Void
    let delete: (TimeEvent) -> Void
    var compact = false
    var body: some View {
        VStack(spacing: 12) {
            Picker("显示方式", selection: $mode) { Text("频率总览").tag(0); Text("折线趋势").tag(1); Text("时间分布").tag(2) }.pickerStyle(.segmented)
            if mode == 0 {
                MarkerFrequencyOverview(events: events, start: start, end: isWeek ? Calendar.current.date(byAdding: .day, value: 7, to: start)! : end, isWeek: isWeek, colors: colors, edit: edit, delete: delete, compact: compact)
            } else {
                MarkerTimelineChart(events: events, start: start, end: end, colors: colors, isWeek: isWeek, line: mode == 1, compact: compact).id(mode)
            }
        }
    }
}

private struct PhoneMarkerEditor: View {
    @ObservedObject var store: PhoneStore
    let event: TimeEvent
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var date: Date
    @State private var failed = false
    init(store: PhoneStore, event: TimeEvent) {
        self.store = store; self.event = event
        _name = State(initialValue: event.kind); _date = State(initialValue: event.occurredAt)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("标记内容", text: $name).textInputAutocapitalization(.never)
                DatePicker("时间", selection: $date, in: ...Date())
                if failed { Text(store.error ?? "无法保存此记录").foregroundStyle(.red) }
            }.navigationTitle("编辑标记").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { if store.updateEvent(event.id, kind: name, at: date) { dismiss() } else { failed = true } }
                            .disabled(store.blocked || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
