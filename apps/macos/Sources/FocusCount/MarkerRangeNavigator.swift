import SwiftUI
import FocusCountCore

struct MarkerRangeNavigator: View {
    let days: Int
    let start: Date
    let visible: Double
    let offset: Double
    var compact = false
    var maximumSpan: Double = 4
    var events: [TimeEvent] = []
    var colors: MarkerColors? = nil
    let change: (Double, Double) -> Void
    @State private var initialOffset: Double?
    @State private var initialVisible: Double?
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let unit = geometry.size.width / Double(max(1, days))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1))
                    Canvas { context, size in
                        let counts = EventAnalytics.dailyCounts(events)
                        let totals = Dictionary(grouping: counts, by: \.day).mapValues { $0.reduce(0) { $0 + $1.count } }
                        let maximum = max(1, totals.values.max() ?? 1)
                        var bases: [Date: Double] = [:]
                        for entry in counts {
                            let day = Calendar.current.dateComponents([.day], from: start, to: entry.day).day ?? 0
                            let height = Double(entry.count) / Double(maximum) * size.height
                            let base = bases[entry.day] ?? 0
                            let rect = CGRect(x: Double(day) * unit, y: size.height - base - height, width: max(1, unit - 1), height: height)
                            context.fill(Path(rect), with: .color((colors?.color(entry.kind) ?? .teal).opacity(0.45)))
                            bases[entry.day] = base + height
                        }
                    }.allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 6).fill(Color.teal.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.teal.opacity(0.55)))
                        .frame(width: max(8, visible * unit)).offset(x: offset * unit)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("markerRangeNavigator")).onChanged { value in
                            if initialOffset == nil { initialOffset = offset }
                            change(min(Double(days) - visible, max(0, (initialOffset ?? offset) + value.translation.width / unit)), visible)
                        }.onEnded { _ in initialOffset = nil })
                    ForEach([false, true], id: \.self) { right in
                        Capsule().fill(Color.teal).frame(width: 5, height: 16).frame(width: 16, height: 28)
                            .contentShape(Rectangle()).offset(x: (offset + (right ? visible : 0)) * unit - 8)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("markerRangeNavigator")).onChanged { value in
                                if initialOffset == nil { initialOffset = offset; initialVisible = visible }
                                let oldOffset = initialOffset ?? offset
                                let oldVisible = initialVisible ?? visible
                                let delta = value.translation.width / unit
                                if right {
                                    let span = min(min(maximumSpan, Double(days) - oldOffset), max(1, oldVisible + delta))
                                    change(oldOffset, span)
                                } else {
                                    let end = oldOffset + oldVisible
                                    let left = min(end - 1, max(max(0, end - maximumSpan), oldOffset + delta))
                                    change(left, end - left)
                                }
                            }.onEnded { _ in initialOffset = nil; initialVisible = nil })
                    }
                }
            }.frame(height: 28).padding(.horizontal, 8)
            if !compact {
            HStack {
                Text(start.formatted(date: .abbreviated, time: .omitted))
                Spacer()
                Text("拖动选框浏览 · 拖动两端缩放")
                Spacer()
                Text(Calendar.current.date(byAdding: .day, value: days - 1, to: start)!.formatted(date: .abbreviated, time: .omitted))
            }.font(.caption2).foregroundStyle(.secondary)
            }
            if Double(days) > visible {
                Slider(value: Binding(get: { offset }, set: { change($0, visible) }), in: 0...max(0.001, Double(days) - visible))
                    .accessibilityLabel("浏览完整日期范围")
                    .controlSize(.mini)
            }
        }.coordinateSpace(name: "markerRangeNavigator")
    }
}
