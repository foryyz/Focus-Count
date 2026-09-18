import SwiftUI
import Charts
import FocusCountCore

struct EventHistoryView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var range = 90
    @State private var kind: String?
    @State private var search = ""
    @State private var deleted = false
    @State private var selectedBucket: Date?
    @State private var deleting: TimeEvent?
    @State private var purging: TimeEvent?
    private var source: [TimeEvent] { store.database.events ?? [] }
    private var scoped: [TimeEvent] { EventAnalytics.records(source, days: range == 0 ? nil : range) }
    private var frequencies: [EventAnalytics.Frequency] {
        EventAnalytics.frequencies(scoped).filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) }
    }
    private var records: [TimeEvent] { scoped.filter { kind == nil || EventAnalytics.label($0.kind) == kind } }
    private var calendar: Calendar { .current }
    private var chartStart: Date {
        range == 0 ? calendar.startOfDay(for: records.last?.occurredAt ?? Date()) : calendar.date(byAdding: .day, value: 1 - range, to: calendar.startOfDay(for: Date()))!
    }
    private var chartEnd: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(Date(), records.first?.occurredAt ?? Date())))! }
    private var component: Calendar.Component {
        let days = calendar.dateComponents([.day], from: chartStart, to: chartEnd).day ?? 0
        return days > 730 ? .month : days > 90 ? .weekOfYear : .day
    }
    private var buckets: [EventAnalytics.Bucket] { EventAnalytics.buckets(records, component: component) }
    private var selection: DateInterval? { selectedBucket.flatMap { calendar.dateInterval(of: component, for: $0) } }
    private var timeline: [TimeEvent] {
        records.filter { event in selection.map { event.occurredAt >= $0.start && event.occurredAt < $0.end } ?? true }
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
                Picker("页面", selection: $deleted) {
                    Text("时间轴").tag(false)
                    Text("最近删除").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            if deleted { trashView }
            else {
                HStack(alignment: .top, spacing: 24) {
                    sidebar.frame(width: 200)
                    Divider()
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(kind ?? "全部标记").font(.title3.weight(.semibold)).lineLimit(1).help(kind ?? "全部标记")
                            Spacer()
                            Picker("日期", selection: $range) {
                                Text("近 30 天").tag(30)
                                Text("近 90 天").tag(90)
                                Text("全部").tag(0)
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                        }
                        HStack(spacing: 32) {
                            metric("标记次数", "\(records.count)")
                            metric("有标记的天数", "\(Set(records.map { calendar.startOfDay(for: $0.occurredAt) }).count)")
                            metric("平均间隔", kind == nil ? "选择一种标记" : EventAnalytics.intervalText(EventAnalytics.frequencies(records).first?.weeksPerOccurrence))
                        }
                        distribution
                        HStack {
                            Text(selectionTitle).font(.headline)
                            Spacer()
                            if selectedBucket != nil { Button("查看全部日期") { selectedBucket = nil }.font(.caption) }
                            Text("\(timeline.count) 次").font(.caption).foregroundStyle(.secondary)
                        }
                        timelineView.id(selectionTitle + (kind ?? "") + String(range))
                    }.frame(maxWidth: .infinity)
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
        }.padding(24).frame(width: 940, height: 680)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: range) { _ in selectedBucket = nil }
            .onChange(of: kind) { _ in selectedBucket = nil }
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
                        Button { kind = item.id } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(item.id).fontWeight(.medium).lineLimit(1); Spacer(); Text("\(item.count) 次").foregroundStyle(.secondary) }
                                Text(EventAnalytics.intervalText(item.weeksPerOccurrence)).font(.caption).foregroundStyle(.secondary)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(kind == item.id ? Color.teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).help(item.id)
                    }
                    if frequencies.isEmpty { Text("没有匹配的标记").font(.caption).foregroundStyle(.secondary).padding(.top) }
                }
            }
            Text("平均间隔 = 同种标记相邻两次的平均时间。按当前日期范围计算，至少需要两次。数值越小，越频繁。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("仅统计未删除标记；旧版 SEX 与 sex 合并展示，原始数据不改动。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
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
                            selectedBucket = selectedBucket == start ? nil : start
                        }
                }
            }.frame(height: 120)
            .overlay { if records.isEmpty { Text("此范围内暂无标记").font(.caption).foregroundStyle(.secondary) } }
        }.padding(14).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
    private var selectionTitle: String {
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
                                Circle().fill(.teal).frame(width: 6, height: 6)
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
