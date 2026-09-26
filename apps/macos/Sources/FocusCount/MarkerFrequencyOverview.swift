import SwiftUI
import FocusCountCore

struct MarkerFrequencyOverview: View {
    let events: [TimeEvent]
    let start: Date
    let end: Date
    let isWeek: Bool
    @ObservedObject var colors: MarkerColors
    let edit: (TimeEvent) -> Void
    let delete: (TimeEvent) -> Void
    var compact = false
    @State private var granularity: MarkerGranularity = .automatic
    @State private var offset = 0.0
    @State private var span = 0.0
    @State private var pendingEdit: TimeEvent?
    @State private var pendingDelete: TimeEvent?
    @State private var selected: MarkerOverviewData.Cell?
    @State private var brush: CGFloat?
    @State private var brushEnd: CGFloat?
    @State private var chartWidth = 600.0
    @State private var pinchSpan: Double?
    private let calendar = Calendar.current
    private var days: Int { max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1) }
    private var visible: Double { span == 0 ? Double(days) : min(Double(days), span) }
    private func date(_ index: Double) -> Date { calendar.date(byAdding: .day, value: Int(index), to: start)! }
    private var rowHeight: CGFloat {
        #if os(iOS)
        44
        #else
        58
        #endif
    }
    private var resolvedGranularity: MarkerGranularity {
        #if os(iOS)
        granularity == .automatic ? (visible <= 14 ? .day : visible <= 100 ? .week : .month) : granularity
        #else
        granularity
        #endif
    }
    private var data: MarkerOverviewData {
        MarkerOverviewData(events: events, start: date(floor(offset)), end: min(end, date(ceil(offset + visible))), granularity: resolvedGranularity)
    }
    private var names: [String] { Array(Set(events.filter { $0.deletedAt == nil }.map { EventAnalytics.label($0.kind) })).sorted() }
    private func zoom(_ value: Double) {
        let center = offset + visible / 2
        span = min(Double(days), max(1, value))
        offset = min(Double(days) - visible, max(0, center - visible / 2))
    }
    private func label(_ bucket: MarkerOverviewData.Bucket, unit: MarkerGranularity) -> String {
        if unit == .day && isWeek { return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: bucket.start) - 1] }
        if unit == .month { return bucket.start.formatted(.dateTime.year(.twoDigits).month()) }
        return bucket.start.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }
    private func scale(_ snapshot: MarkerOverviewData, width: Double) -> (column: Double, unit: Double, limit: Double) {
        let column = max(granularity == .automatic ? 3 : 18, (width - 84) / Double(max(1, snapshot.buckets.count)))
        let limit = max(2, min(42, column - 3))
        let counts = snapshot.cells.map { $0.events.count }.sorted()
        let reference = max(3, counts.isEmpty ? 3 : counts[min(counts.count - 1, Int(Double(counts.count - 1) * 0.95))])
        return (column, min(18, limit / sqrt(Double(reference))), limit)
    }
    var body: some View {
        let snapshot = data
        let sizing = scale(snapshot, width: chartWidth)
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Picker("统计粒度", selection: $granularity) {
                    ForEach(MarkerGranularity.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 130)
                Text(snapshot.granularity.rawValue + "统计").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { zoom(visible * 1.7) } label: { Image(systemName: "minus.magnifyingglass") }.disabled(visible >= Double(days)).help("缩小")
                Button { zoom(visible / 1.7) } label: { Image(systemName: "plus.magnifyingglass") }.disabled(visible <= 1).help("放大")
                Button("查看全貌") { span = 0; offset = 0 }.disabled(visible >= Double(days))
            }
            }
            Text("正在查看 " + date(floor(offset)).formatted(date: .abbreviated, time: .omitted) + " — " + date(ceil(offset + visible) - 1).formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                chart(snapshot)
                #if os(macOS)
                if let selected { inspector(selected).frame(width: 220) }
                #endif
            }
            #if os(iOS)
            if visible < Double(days) {
                Slider(value: $offset, in: 0...max(1, Double(days) - visible)).accessibilityLabel("浏览日期")
            }
            #else
            MarkerRangeNavigator(days: days, start: start, visible: visible, offset: offset, compact: compact, maximumSpan: Double(days), events: events, colors: colors) { position, length in
                span = length; offset = position
            }
            #endif
            if !compact {
            HStack(spacing: 12) {
                Text("面积 = 次数").font(.caption)
                ForEach([1, 3, 10], id: \.self) { count in
                    HStack(spacing: 4) {
                        Circle().fill(Color.teal.opacity(0.6)).frame(width: MarkerOverviewData.diameter(count: count, unit: sizing.unit, limit: sizing.limit), height: MarkerOverviewData.diameter(count: count, unit: sizing.unit, limit: sizing.limit))
                        Text("\(count) 次" + (sizing.unit * sqrt(Double(count)) > sizing.limit + 0.01 ? "*" : "")).font(.caption2)
                    }
                }
                Spacer()
            }.foregroundStyle(.secondary).frame(height: 44)
            Text("* 尺寸封顶，图中显示实际次数 · 空白表示无记录 · 底线表示未完整周期 · 拖选日期栏放大 · 点击气泡查看原始记录")
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        #if os(iOS)
        .sheet(item: $selected, onDismiss: {
            if let event = pendingEdit { pendingEdit = nil; edit(event) }
            if let event = pendingDelete { pendingDelete = nil; delete(event) }
        }) { cell in
            inspector(cell).padding().presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        #endif
        .onChange(of: events) { _ in
            if let selection = selected {
                selected = MarkerOverviewData(events: events, start: selection.bucket.start, end: selection.bucket.end, granularity: resolvedGranularity).cells.first { $0.kind == selection.kind }
            }
        }
    }
    private func chart(_ snapshot: MarkerOverviewData) -> some View {
        GeometryReader { geometry in
            let count = max(1, snapshot.buckets.count)
            let sizing = scale(snapshot, width: geometry.size.width)
            let column = sizing.column
            let plotWidth = column * Double(count)
            let unit = sizing.unit
            let limit = sizing.limit
            let cells = Dictionary(grouping: snapshot.cells, by: \.kind)
            let bucketIndices = Dictionary(uniqueKeysWithValues: snapshot.buckets.enumerated().map { ($0.element.id, $0.offset) })
            ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text("标记").font(.caption).foregroundStyle(.secondary).frame(height: 40)
                    ForEach(names, id: \.self) { name in
                        HStack(spacing: 4) {
                            if let emoji = colors.emojis[name], !emoji.isEmpty { Text(emoji) }
                            else { Circle().fill(colors.color(name)).frame(width: 7, height: 7) }
                            Text(name).lineLimit(1).help(name)
                        }.font(.caption).frame(width: 84, height: rowHeight, alignment: .leading).padding(.bottom, 2)
                    }
                }.frame(width: 84)
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ZStack(alignment: .leading) {
                                Canvas { context, size in
                                    let step = isWeek && snapshot.granularity == .day ? 1 : max(1, Int(ceil(64 / column)))
                                    for (index, bucket) in snapshot.buckets.enumerated() where index % step == 0 {
                                        let x = min(max(26, (Double(index) + 0.5) * column), max(26, size.width - 26))
                                        context.draw(Text(label(bucket, unit: snapshot.granularity)).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: x, y: 20))
                                    }
                                }.accessibilityLabel(snapshot.buckets.map { label($0, unit: snapshot.granularity) }.joined(separator: "，"))
                                if let brush, let brushEnd {
                                    Rectangle().fill(Color.teal.opacity(0.25)).frame(width: abs(brushEnd - brush)).offset(x: min(brush, brushEnd))
                                }
                            }.frame(width: plotWidth, height: 40).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                                    brush = max(0, min(plotWidth, value.startLocation.x))
                                    brushEnd = max(0, min(plotWidth, value.location.x))
                                }.onEnded { _ in
                                    if let first = brush, let last = brushEnd {
                                        let lo = min(count - 1, max(0, Int(min(first, last) / column)))
                                        let hi = min(count - 1, max(lo, Int(max(first, last) / column)))
                                        let a = snapshot.buckets[lo].start
                                        let b = snapshot.buckets[hi].end
                                        offset = Double(calendar.dateComponents([.day], from: start, to: a).day ?? 0)
                                        span = Double(max(1, calendar.dateComponents([.day], from: a, to: b).day ?? 1))
                                    }
                                    brush = nil; brushEnd = nil
                                })
                        }
                        ForEach(names, id: \.self) { name in
                            HStack(spacing: 0) {
                                ZStack(alignment: .leading) {
                                    HStack(spacing: 0) {
                                        ForEach(Array(snapshot.buckets.enumerated()), id: \.element.id) { index, bucket in
                                            Rectangle().fill(Color.primary.opacity(bucket.start > Date() ? 0.012 : index % 2 == 0 ? 0.025 : 0.055))
                                                .overlay(alignment: .top) {
                                                    if bucket.start > Date() { Text("未到来").font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1) }
                                                }
                                                .overlay(alignment: .bottom) { if bucket.partial { Rectangle().fill(Color.secondary.opacity(0.35)).frame(height: 2) } }
                                                .frame(width: column)
                                        }
                                    }
                                    ForEach(cells[name] ?? []) { cell in
                                        if let index = bucketIndices[cell.bucket.id] {
                                            bubble(cell, unit: unit, limit: limit)
                                                .position(x: (Double(index) + 0.5) * column, y: rowHeight / 2)
                                        }
                                    }
                                }.frame(width: plotWidth, height: rowHeight)
                            }.padding(.bottom, 2)
                        }
                        if names.isEmpty { Text("此范围没有标记").foregroundStyle(.secondary).padding(40) }
                    }.frame(minWidth: max(1, geometry.size.width - 84), alignment: .leading)
                }
            }
            }.onAppear { chartWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { chartWidth = $0 }
                .simultaneousGesture(MagnificationGesture().onChanged { value in
                if pinchSpan == nil { pinchSpan = visible }
                zoom((pinchSpan ?? visible) / value)
            }.onEnded { _ in pinchSpan = nil })
        }.frame(minHeight: compact ? 90 : 190, maxHeight: .infinity)
    }
    private func bubble(_ cell: MarkerOverviewData.Cell, unit: Double, limit: Double) -> some View {
        let diameter = MarkerOverviewData.diameter(count: cell.events.count, unit: unit, limit: limit)
        let capped = unit * sqrt(Double(cell.events.count)) > limit + 0.01
        return Button { selected = cell } label: {
            ZStack {
                Circle().fill(colors.color(cell.kind).opacity(0.68))
                Circle().stroke(colors.color(cell.kind).opacity(0.8), lineWidth: 1)
                if diameter >= 17, let emoji = colors.emojis[cell.kind], !emoji.isEmpty {
                    Text(emoji).font(.system(size: max(12, diameter * 0.65)))
                }
                if capped && limit >= 14 { Text("\(cell.events.count)").font(.system(size: 9, weight: .bold)).padding(2).background(.regularMaterial, in: Capsule()).offset(y: diameter / 2) }
            }.frame(width: max(3, diameter), height: max(3, diameter)).frame(minWidth: 14, minHeight: 24)
        }.buttonStyle(.plain)
            .help(cell.kind + " · \(cell.events.count) 次\n" + cell.bucket.start.formatted(date: .abbreviated, time: .omitted) + " — " + cell.bucket.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted) + (cell.bucket.partial ? "\n未完整周期" : ""))
            .accessibilityLabel(cell.kind + "，" + cell.bucket.start.formatted(date: .abbreviated, time: .omitted) + "，\(cell.events.count) 次，查看详情")
    }
    private func actionIcon(_ name: String) -> some View {
        #if os(iOS)
        Image(systemName: name).frame(minWidth: 44, minHeight: 44)
        #else
        Image(systemName: name)
        #endif
    }
    private func inspector(_ cell: MarkerOverviewData.Cell) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            HStack {
                Text((colors.emojis[cell.kind] ?? "") + " " + cell.kind).font(.headline).lineLimit(1)
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭详情")
            }
            Text("\(cell.events.count) 次").font(.title2.weight(.semibold))
            Text(cell.bucket.start.formatted(date: .abbreviated, time: .omitted) + " — " + cell.bucket.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            if cell.bucket.partial { Text("未完整周期 · 已覆盖 \(max(1, calendar.dateComponents([.day], from: cell.bucket.start, to: min(cell.bucket.end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!)).day ?? 1)) 天").font(.caption2).foregroundStyle(.secondary) }
            if calendar.dateComponents([.day], from: cell.bucket.start, to: cell.bucket.end).day ?? 1 > 1 {
                Button("展开每日分布") {
                    offset = Double(calendar.dateComponents([.day], from: start, to: cell.bucket.start).day ?? 0)
                    span = Double(max(1, calendar.dateComponents([.day], from: cell.bucket.start, to: cell.bucket.end).day ?? 1))
                    granularity = .day; selected = nil
                }
            }
            let hours = EventAnalytics.hours(cell.events)
            let peak = max(1, hours.max() ?? 1)
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<24, id: \.self) { hour in
                        Rectangle().fill(colors.color(cell.kind).opacity(hours[hour] == 0 ? 0.12 : 0.8))
                            .frame(height: max(2, Double(hours[hour]) / Double(peak) * 24))
                            .help("\(hour):00 · \(hours[hour]) 次")
                    }
                }.frame(height: 24, alignment: .bottom)
                HStack { Text("00:00"); Spacer(); Text("12:00"); Spacer(); Text("24:00") }.font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(cell.events) { event in
                        HStack {
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Spacer()
                            Button {
                                #if os(iOS)
                                pendingEdit = event; selected = nil
                                #else
                                edit(event)
                                #endif
                            } label: { actionIcon("pencil") }.help("编辑标记")
                            Button {
                                #if os(iOS)
                                pendingDelete = event; selected = nil
                                #else
                                delete(event)
                                #endif
                            } label: { actionIcon("trash") }.help("移至最近删除")
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}
