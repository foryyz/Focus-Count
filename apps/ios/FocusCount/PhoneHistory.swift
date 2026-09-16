import SwiftUI
import Charts
import FocusCountCore

struct PhoneHistory: View {
    @ObservedObject var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleted = false
    @State private var subject = ""
    @State private var focus = ""
    @State private var allDates = true
    @State private var start = Calendar.current.date(byAdding: .day, value: -29, to: .now)!
    @State private var end = Date()
    @State private var filters = false
    @State private var editing: StudySession?
    @State private var deleting: StudySession?
    @State private var purging: Set<UUID> = []
    @State private var selectedDay: Date?
    private var records: [StudySession] {
        let lower = Calendar.current.startOfDay(for: start)
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!
        return store.state.sessions.filter {
            ($0.deletedAt != nil) == deleted && (subject.isEmpty || $0.subject == subject) &&
            (focus.isEmpty || $0.focus == focus) && (allDates || ($0.startedAt >= lower && $0.startedAt < upper))
        }.sorted { $0.startedAt > $1.startedAt }
    }
    private var dayTotals: [Date: Double] {
        Dictionary(grouping: records, by: { Calendar.current.startOfDay(for: $0.startedAt) }).mapValues { $0.reduce(0) { $0 + $1.activeSeconds } }
    }
    private var chartDates: ClosedRange<Date> {
        let lower = dayTotals.keys.min() ?? Calendar.current.startOfDay(for: .now)
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: dayTotals.keys.max() ?? lower)!
        return lower...upper
    }
    private var chartDayStride: Int {
        max(1, (Calendar.current.dateComponents([.day], from: chartDates.lowerBound, to: chartDates.upperBound).day ?? 1) / 5)
    }
    private var subjectTotals: [String: Double] {
        Dictionary(grouping: records, by: \.subject).mapValues { $0.reduce(0) { $0 + $1.activeSeconds } }
    }
    private var isFiltered: Bool { !allDates || !subject.isEmpty || !focus.isEmpty }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("记录范围", selection: $deleted) {
                        Text("专注记录").tag(false); Text("最近删除").tag(true)
                    }.pickerStyle(.segmented).labelsHidden()
                    HStack {
                        Button { filters = true } label: { Label(isFiltered ? "已筛选" : "筛选记录", systemImage: "line.3.horizontal.decrease") }
                        Spacer()
                        if isFiltered { Button("重置") { allDates = true; subject = ""; focus = ""; selectedDay = nil } }
                    }
                }.listRowBackground(Color.clear)
                if deleted { Section { Button("清空全部", role: .destructive) { purging = Set(store.state.sessions.filter { $0.deletedAt != nil }.map(\.id)) }
                    .disabled(store.blocked || !store.state.sessions.contains { $0.deletedAt != nil }) } }
                if !deleted {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("有效专注时间").font(.caption).foregroundStyle(.secondary)
                            Text(phoneDuration(records.reduce(0) { $0 + $1.activeSeconds })).font(.largeTitle.monospacedDigit().weight(.light))
                            Text("\(records.count) 次专注 · \(dayTotals.count) 天").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    if !records.isEmpty {
                        Section {
                            Chart(dayTotals.keys.sorted(), id: \.self) { day in
                                BarMark(x: .value("日期", day, unit: .day), y: .value("分钟", (dayTotals[day] ?? 0) / 60))
                                    .foregroundStyle(Color.teal.gradient).cornerRadius(3)
                            }
                            .chartXScale(domain: chartDates)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: chartDayStride)) {
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits))
                                }
                            }
                            .chartYAxisLabel("分钟").chartXSelection(value: $selectedDay).frame(height: 150)
                            .onChange(of: selectedDay) { _, value in
                                if let value { start = value; end = value; allDates = false }
                            }
                            Text("按开始日期统计 · 轻点图表筛选当天")
                                .font(.caption2).foregroundStyle(.secondary)
                        } header: { Text("每日时长") }
                        Section("活动分布") {
                            ForEach(subjectTotals.keys.sorted { subjectTotals[$0]! > subjectTotals[$1]! }, id: \.self) { name in
                                Button { subject = name } label: {
                                    VStack(spacing: 8) {
                                        HStack { Text(name).foregroundStyle(.primary); Spacer(); Text(phoneDuration(subjectTotals[name] ?? 0)).foregroundStyle(.secondary).monospacedDigit() }.font(.subheadline)
                                        ProgressView(value: subjectTotals[name] ?? 0, total: max(subjectTotals.values.max() ?? 1, 1)).tint(.teal)
                                    }.padding(.vertical, 4)
                                }.buttonStyle(.plain).accessibilityHint("筛选此活动")
                            }
                        }
                    }
                }
                Section {
                    if records.isEmpty {
                        ContentUnavailableView(deleted ? "没有已删除记录" : "还没有匹配的记录", systemImage: deleted ? "trash" : "calendar", description: Text("试试调整筛选，或补记一次专注。"))
                    }
                    ForEach(records) { session in
                        if deleted {
                            VStack(alignment: .leading) { row(session); HStack { Button("恢复") { store.delete(session, restore: true) }; Spacer(); Button("彻底删除", role: .destructive) { purging = [session.id] } }.buttonStyle(.borderless).disabled(store.blocked) }
                        } else {
                            Button { editing = session } label: { row(session) }.buttonStyle(.plain)
                                .disabled(store.blocked)
                                .swipeActions {
                                    Button(role: .destructive) { deleting = session } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                } header: { Text(deleted ? "最近删除" : "记录明细 · \(records.count) 条") }
                footer: { if deleted { Text("可恢复或彻底删除。清空全部包含筛选外的记录。") } }
                if let error = store.error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle("专注记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("计时", systemImage: "chevron.left") } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = StudySession(startedAt: .now.addingTimeInterval(-1800), endedAt: .now, activeSeconds: 1800, subject: "", focus: "A") } label: { Label("补记", systemImage: "plus") }.disabled(store.blocked)
                }
            }
        .alert("彻底删除这 \(purging.count) 条记录？", isPresented: Binding(get: { !purging.isEmpty }, set: { if !$0 { purging = [] } })) {
            Button("取消", role: .cancel) { purging = [] }
            Button("彻底删除", role: .destructive) { store.permanentlyDelete(purging); purging = [] }
        } message: { Text("记录及其历史版本将从当前数据中移除，无法在应用内恢复。导入旧文件不会重新出现。已有备份文件不受影响。") }
            .sheet(item: $editing) { session in
                let isNew = !store.state.sessions.contains { $0.id == session.id }
                RecordEditor(store: store, session: session, onSave: {
                    if isNew { deleted = false; allDates = true; subject = ""; focus = ""; selectedDay = nil }
                })
            }
            .sheet(isPresented: $filters) { filterSheet }
            .confirmationDialog("删除这条专注记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("移至最近删除", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil }
            } message: { Text("删除后仍可恢复。") }
        }
    }
    private func row(_ session: StudySession) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(session.subject).font(.headline).lineLimit(2)
                Spacer()
                Text(session.focus).font(.caption.bold()).foregroundStyle(.teal).padding(6).background(Color.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text(phoneDuration(session.activeSeconds)).monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("日期") {
                    Toggle("全部日期", isOn: $allDates)
                    if !allDates {
                        DatePicker("从", selection: $start, displayedComponents: .date)
                        DatePicker("至", selection: $end, displayedComponents: .date)
                        if Calendar.current.startOfDay(for: start) > Calendar.current.startOfDay(for: end) { Text("开始日期不能晚于结束日期").foregroundStyle(.orange) }
                    }
                }
                Section {
                    Picker("活动", selection: $subject) {
                        Text("全部活动").tag("")
                        ForEach(Array(Set(store.state.sessions.map(\.subject))).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("专注度", selection: $focus) {
                        Text("全部").tag("")
                        ForEach(["S", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) }
                    }
                }
            }.navigationTitle("筛选记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { filters = false } } }
        }.presentationDetents([.medium, .large])
    }
}


struct PhoneEventHistory: View {
    @ObservedObject var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleted = false
    @State private var deleting: TimeEvent?
    @State private var purging: Set<UUID> = []
    @State private var message: String?
    private var events: [TimeEvent] {
        (store.state.events ?? []).filter { ($0.deletedAt != nil) == deleted }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        let time = Date()
                        if store.markEvent(at: time) {
                            deleted = false
                            message = "已标记 SEX · " + time.formatted(date: .omitted, time: .standard)
                        }
                    } label: { Label("标记 SEX 一次", systemImage: "plus.circle.fill") }
                        .disabled(store.blocked)
                    if let message { Text(message).font(.footnote).foregroundStyle(.teal) }
                } footer: { Text("仅记录当下日期时间，不计时、不影响当前专注。每点一次记录一次，对应 Mac 的 !sex。") }
                Section {
                    Picker("范围", selection: $deleted) {
                        Text("时间标记").tag(false)
                        Text("最近删除").tag(true)
                    }.pickerStyle(.segmented).labelsHidden()
                    if deleted {
                        Button("清空全部标记", role: .destructive) {
                            purging = Set(events.map(\.id))
                        }.disabled(events.isEmpty || store.blocked)
                    }
                }
                Section("\(events.count) 次") {
                    if events.isEmpty {
                        ContentUnavailableView(deleted ? "没有已删除标记" : "暂无时间标记", systemImage: "mappin.circle")
                    }
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(event.kind).font(.headline)
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                if deleted {
                                    Button("恢复") { store.setEventDeleted(event.id, deleted: false) }
                                    Spacer()
                                    Button("彻底删除", role: .destructive) { purging = [event.id] }
                                } else {
                                    Spacer()
                                    Button("删除", role: .destructive) { deleting = event }
                                }
                            }.buttonStyle(.borderless).disabled(store.blocked)
                        }.padding(.vertical, 5)
                    }
                }
                if let error = store.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("时间标记").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .alert("删除这次时间标记？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("移至最近删除", role: .destructive) {
                    if let deleting { store.setEventDeleted(deleting.id, deleted: true) }
                    deleting = nil
                }
            }
            .alert("彻底删除这 \(purging.count) 次标记？", isPresented: Binding(get: { !purging.isEmpty }, set: { if !$0 { purging = [] } })) {
                Button("取消", role: .cancel) { purging = [] }
                Button("彻底删除", role: .destructive) { store.purgeEvents(purging); purging = [] }
            } message: { Text("无法在应用内恢复，导入旧文件不会重新出现。已有独立备份不受影响。") }
        }
    }
}
