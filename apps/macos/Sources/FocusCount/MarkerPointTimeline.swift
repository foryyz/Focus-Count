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
            let hourHeight = max(1, geometry.size.height - 60) / 24
            let items = MarkerPointLayout.items(events: events, start: start, offset: offset, visibleDays: visibleDays, width: width, hourHeight: hourHeight)
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

                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            for hour in 0...24 {
                                let y = 14 + Double(hour) * hourHeight
                                var path = Path(); path.move(to: CGPoint(x: 48, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(.secondary.opacity(hour % 6 == 0 ? 0.3 : 0.13)), lineWidth: 1)
                                if hour % 6 == 0 { context.draw(Text(String(format: "%02d:00", hour)).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: 42, y: y), anchor: .trailing) }
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
                        ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            for item in items where abs(item.y - item.anchorY) > 2 {
                                let color = colors.color(EventAnalytics.label(item.events[0].kind))
                                let anchor = CGPoint(x: 48 + item.x, y: 14 + item.anchorY)
                                var path = Path(); path.move(to: anchor); path.addLine(to: CGPoint(x: 48 + item.x, y: 14 + item.y))
                                context.stroke(path, with: .color(color.opacity(0.45)), lineWidth: 1)
                                context.fill(Path(ellipseIn: CGRect(x: anchor.x - 2, y: anchor.y - 2, width: 4, height: 4)), with: .color(color))
                            }
                        }.allowsHitTesting(false)
                        ForEach(items) { item in
                            Button { expanded = item } label: {
                                let name = EventAnalytics.label(item.events[0].kind)
                                if let emoji = colors.emojis[name], !emoji.isEmpty {
                                    if item.grouped {
                                        ZStack {
                                            Circle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                                            Circle().strokeBorder(colors.color(name).opacity(0.85), lineWidth: 2)
                                            Text(emoji).font(.system(size: item.diameter - 10))
                                                .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 0, x: 1, y: 0)
                                                .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 0, x: -1, y: 0)
                                                .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 0, x: 0, y: 1)
                                                .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 0, x: 0, y: -1)
                                        }.frame(width: item.diameter, height: item.diameter)
                                    } else {
                                        Text(emoji).font(.system(size: item.diameter - 2)).frame(width: item.diameter, height: item.diameter)
                                    }
                                } else {
                                    Circle().fill(colors.color(name)).frame(width: item.diameter * 0.65, height: item.diameter * 0.65).frame(width: item.diameter, height: item.diameter)
                                }
                            }.buttonStyle(.plain)
                                .help(item.events.map { $0.kind + " · " + $0.occurredAt.formatted(date: .abbreviated, time: .standard) }.joined(separator: "\n"))
                                .accessibilityLabel(item.grouped ? item.events[0].kind + "，共 \(item.events.count) 次，展开" : item.events[0].kind + " " + item.events[0].occurredAt.formatted(date: .abbreviated, time: .standard))
                                .position(x: 48 + item.x, y: 14 + item.y)
                        }
                        }.mask(Rectangle().padding(.leading, 48))
                    }.frame(height: 24 * hourHeight + 28).clipped()

            }
        }.frame(minHeight: 240)
            .popover(item: $expanded) { item in
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.grouped ? item.events[0].kind + " · \(item.events.count) 次" : "时间标记").font(.headline)
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
