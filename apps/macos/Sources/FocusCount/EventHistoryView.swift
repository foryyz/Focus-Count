import SwiftUI
import FocusCountCore

struct EventHistoryView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var range = -1
    @State private var kind: String?
    @State private var search = ""
    @State private var page = 2
    @StateObject private var colors = MarkerColors()
    @State private var selectedHour: Int?
    @State private var deleting: TimeEvent?
    @State private var purging: TimeEvent?
    private var source: [TimeEvent] { store.database.events ?? [] }
    private var scoped: [TimeEvent] {
        let start = EventAnalytics.periodStart(range: range)
        return EventAnalytics.records(source, days: nil).filter { ($0.occurredAt >= (start ?? .distantPast) && $0.occurredAt < todayEnd) }
    }
    private var periodStart: Date {
        EventAnalytics.periodStart(range: range) ?? calendar.startOfDay(for: EventAnalytics.records(source, days: nil).last(where: { $0.occurredAt < todayEnd })?.occurredAt ?? Date())
    }
    private func weekly(_ count: Int) -> String { EventAnalytics.weeklyText(EventAnalytics.weeklyRate(count: count, start: periodStart)) }
    private var todayEnd: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))! }
    private var allNames: [String] {
        var seen: Set<String> = []
        return source.sorted { $0.occurredAt == $1.occurredAt ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt < $1.occurredAt }
            .map { EventAnalytics.label($0.kind) }.filter { seen.insert($0).inserted }
    }
    private var frequencies: [EventAnalytics.Frequency] {
        EventAnalytics.frequencies(scoped).filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) }
    }
    private var records: [TimeEvent] { scoped.filter { kind == nil || EventAnalytics.label($0.kind) == kind } }
    private var calendar: Calendar { .current }
    private var timeline: [TimeEvent] {
        records.filter { selectedHour == nil || calendar.component(.hour, from: $0.occurredAt) == selectedHour }
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
                    Text("可视化").tag(2)
                    Text("时间轴").tag(0)
                    Text("最近删除").tag(1)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            if page == 1 { trashView }
            else {
                HStack(alignment: .top, spacing: 24) {
                    sidebar.frame(width: 250)
                    Divider()
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(kind ?? "全部标记").font(.title3.weight(.semibold)).lineLimit(1).help(kind ?? "全部标记")
                            Spacer()
                            Picker("日期", selection: $range) {
                                Text("本周").tag(-1)
                                Text("30 天").tag(30)
                                Text("全部").tag(0)
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 280)
                        }
                        HStack(spacing: 28) {
                            metric("标记次数", "\(records.count) 次")
                            metric("平均频率", weekly(records.count))
                            metric("最近一次", records.first?.occurredAt.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        }
                        if page == 2 {
                            MarkerTimelineChart(events: records, start: periodStart, end: todayEnd, colors: colors, isWeek: range == -1)
                                .id(String(range))
                        } else {
                        heatmap
                        Divider()
                        HStack {
                            Text(selectionTitle).font(.headline)
                            Spacer()
                            if selectedHour != nil {
                                Button("清除时段筛选") { selectedHour = nil }.font(.caption)
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
            .onAppear { colors.ensure(allNames) }
            .onChange(of: allNames) { _ in colors.ensure(allNames) }
            .onChange(of: range) { _ in selectedHour = nil }
            .onChange(of: kind) { _ in selectedHour = nil }
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
            Button { kind = nil; selectedHour = nil } label: {
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

                            }
                            TextField("—", text: Binding(get: { colors.emojis[item.id] ?? "" }, set: { colors.setEmoji($0, for: item.id) }))
                                .textFieldStyle(.roundedBorder).frame(width: 40).help("手动设置 emoji；留空使用标记颜色")
                                .accessibilityLabel(item.id + " 的 emoji")
                            Button { kind = kind == item.id ? nil : item.id } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack { Text(item.id).fontWeight(.medium).lineLimit(1); Spacer(); Text("\(item.count) 次").foregroundStyle(.secondary) }
                                    Text(weekly(item.count)).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(item.id)
                        }.padding(10).background(kind == item.id ? colors.color(item.id).opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    if frequencies.isEmpty { Text("没有匹配的标记").font(.caption).foregroundStyle(.secondary).padding(.top) }
                }
            }
            Text("平均每周次数 = 范围内次数 ÷ 范围天数 × 7。本周按周一至今天计算；30 天按 30 天；全部按最早标记至今天计算，包含无记录的日期。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("点击名称查看时段分布；点击色块调整颜色。颜色保存在这台 Mac，旧标记颜色不会因新标记加入而变化。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                            selectedHour = selectedHour == hour ? nil : hour
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
    private var selectionTitle: String {
        if let selectedHour { return String(format: "%02d:00–%02d:00 · 最新在前", selectedHour, selectedHour + 1) }
        return "最新在前"
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
