import SwiftUI
import FocusCountCore

func duration(_ seconds: Double) -> String { phoneDuration(seconds) }

extension PhoneStore {
    func today(at date: Date = Date()) -> TodaySummary {
        TodaySummary(database: Database(events: state.events, sessions: state.sessions), now: date)
    }
}

struct PhoneTodaySheet: View {
    @ObservedObject var store: PhoneStore
    @ObservedObject var appearance: FocusAppearanceStore
    @StateObject private var colors = MarkerColors()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let summary = store.today(at: context.date)
                List {
                    Section(context.date.formatted(.dateTime.month().day())) {
                        if summary.activities.isEmpty { Text("今天的第一段专注，从这里开始。").foregroundStyle(.secondary) }
                        ForEach(summary.activities) { item in
                            VStack(spacing: 8) {
                                HStack { Text(item.name); Spacer(); Text(phoneDuration(item.seconds)).monospacedDigit().foregroundStyle(.secondary) }.font(.subheadline)
                                ProgressView(value: item.seconds, total: max(1, summary.activities.first?.seconds ?? 1)).tint(appearance.color("activity:" + item.name))
                            }.padding(.vertical, 4)
                        }
                    }
                    Section("时间标记") {
                        if summary.events.isEmpty { Text("今天还没有标记").foregroundStyle(.secondary) }
                        ForEach(summary.events) { event in
                            HStack {
                                let name = EventAnalytics.label(event.kind)
                                Text(colors.emojis[name] ?? "●").foregroundStyle(colors.color(name))
                                Text(event.kind)
                                Spacer()
                                Text(event.occurredAt.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
                            }.font(.subheadline)
                        }
                    }
                    Section {
                        Text("\(summary.sessions.count) 次专注 · \(summary.events.count) 次标记")
                    } footer: { Text("仅统计已保存记录；跨午夜专注按开始日期归属。") }
                }
            }.navigationTitle("今日概览").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onAppear {
                    appearance.ensureColors(store.subjects)
                    colors.ensure((store.state.events ?? []).map { EventAnalytics.label($0.kind) })
                }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

struct PhoneTargetSettings: View {
    @ObservedObject var store: TargetCountdownStore
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var name = ""
    @State private var emoji = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    @State private var includesTime = false
    @State private var showOnHome = true
    @State private var deleting = false
    private var concealed: Bool { store.target?.hidden == true && !revealed }
    var body: some View {
        NavigationStack {
            Form {
                if let error = store.error { Text(error).foregroundStyle(.red) }
                if concealed {
                    Section {
                        Label("目标已隐藏", systemImage: "eye.slash")
                        Button("查看并编辑目标") { load(); revealed = true }
                    } footer: { Text("查看详情不会自动恢复首页显示。") }
                } else {
                    Section {
                        TextField("目标名称", text: $name)
                        TextField("Emoji（可选）", text: $emoji).onChange(of: emoji) { _, value in emoji = String(value.prefix(1)) }
                        DatePicker("日期", selection: $date, displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                        Toggle("指定具体时间", isOn: $includesTime)
                    } header: { Text("目标") } footer: { if !includesTime { Text("倒数至所选日期的本地时间 00:00。") } }
                    Section {
                        Toggle("在首页显示目标与倒数", isOn: $showOnHome)
                    } footer: { Text("目标随 JSON 导入导出同步，隐藏状态仅保存在此设备。首次导入目标默认隐藏。") }
                    if store.target != nil { Button("删除目标", role: .destructive) { deleting = true } }
                }
            }.navigationTitle("目标日期").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if !concealed {
                            Button("保存") {
                                if store.save(TargetDate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji, date: date, includesTime: includesTime, hidden: !showOnHome)) { dismiss() }
                            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .onAppear { if !concealed { load() } }
                .confirmationDialog("删除目标日期？删除将随数据交换同步。", isPresented: $deleting, titleVisibility: .visible) {
                    Button("删除", role: .destructive) { if store.remove() { dismiss() } }
                }
        }
    }
    private func load() {
        guard let target = store.target else { return }
        name = target.name; emoji = target.emoji; date = target.date
        includesTime = target.includesTime; showOnHome = !target.hidden
    }
}
