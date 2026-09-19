import SwiftUI
import FocusCountCore

struct MarkerPointTimeline: View {
    let events: [TimeEvent]
    let start: Date
    let days: Int
    let offset: Double
    let visibleDays: Double
    let isWeek: Bool
    @ObservedObject var colors: MarkerColors
    let zoomTo: (Date, Date) -> Void
    @State private var expanded: MarkerPointLayout.Item?
    private let hourHeight = 30.0
    private let calendar = Calendar.current
    private func date(_ day: Int) -> Date { calendar.date(byAdding: .day, value: day, to: start)! }
    private func label(_ day: Int) -> String {
        if isWeek { return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: date(day)) - 1] }
        return date(day).formatted(.dateTime.month().day())
    }
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 48)
            let dayWidth = width / visibleDays
            let step = max(1, Int(ceil(45 / dayWidth)))
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Text("时间").font(.caption2).foregroundStyle(.secondary).frame(width: 40)
                    ForEach(0..<days, id: \.self) { day in
                        if day % step == 0 && Double(day) >= floor(offset) && Double(day) < ceil(offset + visibleDays) {
                            Text(label(day)).font(.system(size: 11, weight: .medium))
                                .position(x: 48 + (Double(day) + 0.5 - offset) * dayWidth, y: 12)
                        }
                    }
                }.frame(height: 28).clipped()
                ScrollViewReader { reader in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            for hour in 0...24 {
                                let y = 14 + Double(hour) * hourHeight
                                var path = Path(); path.move(to: CGPoint(x: 48, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(.secondary.opacity(hour % 6 == 0 ? 0.3 : 0.13)), lineWidth: 1)
                                context.draw(Text(String(format: "%02d:00", hour)).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: 42, y: y), anchor: .trailing)
                            }
                            for day in max(0, Int(floor(offset)))..<min(days, Int(ceil(offset + visibleDays))) {
                                let left = 48 + (Double(day) - offset) * dayWidth
                                if day % 2 == 0 {
                                    context.fill(Path(CGRect(x: max(48, left), y: 14, width: max(0, min(size.width, left + dayWidth) - max(48, left)), height: 24 * hourHeight)), with: .color(.teal.opacity(0.045)))
                                }
                                var path = Path(); path.move(to: CGPoint(x: left, y: 14)); path.addLine(to: CGPoint(x: left, y: 14 + 24 * hourHeight))
                                if left >= 48 { context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 1) }
                            }
                        }.frame(height: 24 * hourHeight + 28)
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                Color.clear.frame(height: hourHeight).id(hour)
                            }
                        }.padding(.top, 14).allowsHitTesting(false)
                        ForEach(MarkerPointLayout.items(events: events, start: start, offset: offset, visibleDays: visibleDays, width: width)) { item in
                            Button { expanded = item } label: {
                                if item.grouped {
                                    Text("+\(item.events.count)").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 4).frame(height: 22)
                                        .background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(Color.secondary.opacity(0.3)))
                                } else {
                                    let name = EventAnalytics.label(item.events[0].kind)
                                    if let emoji = colors.emojis[name], !emoji.isEmpty { Text(emoji).font(.system(size: 20)).frame(width: 24, height: 24) }
                                    else { Circle().fill(colors.color(name)).frame(width: 12, height: 12).frame(width: 24, height: 24) }
                                }
                            }.buttonStyle(.plain)
                                .help(item.events.map { $0.kind + " · " + $0.occurredAt.formatted(date: .abbreviated, time: .standard) }.joined(separator: "\n"))
                                .accessibilityLabel(item.grouped ? "展开 \(item.events.count) 条标记" : item.events[0].kind + " " + item.events[0].occurredAt.formatted(date: .abbreviated, time: .standard))
                                .position(x: 48 + item.x, y: 14 + item.y)
                        }
                    }.frame(height: 24 * hourHeight + 28).clipped()
                }.task {
                    await Task.yield()
                    let firstHour = events.map { calendar.component(.hour, from: $0.occurredAt) }.min() ?? 0
                    reader.scrollTo(min(16, max(0, firstHour - 1)), anchor: .top)
                }
                }
            }
        }.frame(minHeight: 240)
            .popover(item: $expanded) { item in
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.grouped ? "\(item.events.count) 条标记" : "时间标记").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(item.events.sorted { $0.occurredAt < $1.occurredAt }) { event in
                                HStack {
                                    Text(colors.emojis[EventAnalytics.label(event.kind)] ?? "●").foregroundStyle(colors.color(EventAnalytics.label(event.kind)))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.kind)
                                        Text(event.occurredAt.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }.frame(maxHeight: 240)
                    if item.grouped {
                        Button("放大到这些日期") {
                            zoomTo(item.events.map(\.occurredAt).min()!, item.events.map(\.occurredAt).max()!)
                            expanded = nil
                        }
                    }
                }.padding(18).frame(width: 280)
            }
    }
}
