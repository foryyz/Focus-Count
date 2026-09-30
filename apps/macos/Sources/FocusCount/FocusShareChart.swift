import SwiftUI
#if os(macOS)
import AppKit
#endif

struct FocusShareSlice: Identifiable {
    let id: String
    let name: String
    let seconds: Double
    let source: FocusBreakdown?
    static func make(_ items: [FocusBreakdown]) -> [FocusShareSlice] {
        let positive = items.filter { $0.seconds > 0 }
        let limit = positive.count > 6 ? 5 : 6
        var result = positive.prefix(limit).map { FocusShareSlice(id: "item:" + $0.id, name: $0.name, seconds: $0.seconds, source: $0) }
        if positive.count > 6 {
            let rest = positive.dropFirst(5)
            result.append(FocusShareSlice(id: "remainder", name: "其他（\(rest.count)项）", seconds: rest.reduce(0) { $0 + $1.seconds }, source: nil))
        }
        return result
    }
}

struct FocusShareChart: View {
    let items: [FocusBreakdown]
    let activityCount: Int
    let pie: Bool
    let color: (FocusBreakdown) -> Color
    private var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    private var slices: [FocusShareSlice] { FocusShareSlice.make(items) }
    private var total: Double { items.reduce(0) { $0 + $1.seconds } }
    var body: some View {
        #if os(macOS)
        MacFocusShareDiagram(slices: slices, total: total, activityCount: activityCount, pie: pie, color: color)
        #else
        GeometryReader { geometry in
            let size = min(geometry.size.height - 12, geometry.size.width * (pie ? 0.55 : 0.78))
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                Circle().fill(Color.secondary.opacity(0.08)).frame(width: size, height: size).position(center)
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    let start = slices.prefix(index).reduce(0) { $0 + $1.seconds } / (total > 0 ? total : 1)
                    let end = start + slice.seconds / (total > 0 ? total : 1)
                    let middle = (start + end) * Double.pi - Double.pi / 2
                    ShareSector(start: start, end: end, hole: pie ? 0 : 0.70)
                        .fill(slice.source.map(color) ?? Color.secondary)
                        .frame(width: size, height: size).position(center)
                        .help("\(slice.name) · \(duration(slice.seconds)) · \(percent(slice.seconds))")
                        .accessibilityLabel("\(slice.name)，\(percent(slice.seconds))，\(duration(slice.seconds))")
                    if pie && slice.seconds / (total > 0 ? total : 1) >= 0.12 {
                        VStack(spacing: 2) {
                            Text(slice.name).lineLimit(1)
                            Text(percent(slice.seconds)).fontWeight(.semibold).monospacedDigit()
                        }.font(.system(size: size < 180 ? 10 : 12)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.7), radius: 2)
                            .frame(width: max(42, size * 0.36))
                            .position(x: center.x + cos(middle) * size * 0.29, y: center.y + sin(middle) * size * 0.29)
                            .help(slice.name)
                    } else if pie {
                        let right = cos(middle) >= 0
                        let indices = slices.indices.filter { candidate in
                            let offset = slices.prefix(candidate).reduce(0) { $0 + $1.seconds }
                            let angle = (offset + slices[candidate].seconds / 2) / (total > 0 ? total : 1) * Double.pi * 2 - Double.pi / 2
                            return (cos(angle) >= 0) == right
                        }.sorted { left, rightIndex in angleY(left) < angleY(rightIndex) }
                        let rank = indices.firstIndex(of: index) ?? 0
                        let y = geometry.size.height * Double(rank + 1) / Double(indices.count + 1)
                        let labelX = right ? geometry.size.width - 43 : 43
                        Path { path in
                            path.move(to: CGPoint(x: center.x + cos(middle) * size / 2, y: center.y + sin(middle) * size / 2))
                            path.addLine(to: CGPoint(x: right ? labelX - 40 : labelX + 40, y: y))
                        }.stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        VStack(spacing: 2) {
                            Text(slice.name).lineLimit(1).help(slice.name)
                            Text(percent(slice.seconds)).fontWeight(.semibold).monospacedDigit()
                        }.font(.caption).frame(width: 82).position(x: labelX, y: y)
                    }
                }
                if !pie || total == 0 {
                    if !pie { Circle().fill(background).frame(width: size * 0.70, height: size * 0.70).position(center) }
                    VStack(spacing: 6) {
                        Text("\(activityCount) 个活动").font(.caption).foregroundStyle(.secondary)
                        Text(duration(total)).font(.system(size: size > 190 ? 22 : 15, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("总有效时长").font(.caption2).foregroundStyle(.secondary)
                    }.position(center).allowsHitTesting(false)
                }
            }
        }
        #endif
    }
    private func angleY(_ index: Int) -> Double {
        let start = slices.prefix(index).reduce(0) { $0 + $1.seconds }
        return sin((start + slices[index].seconds / 2) / (total > 0 ? total : 1) * Double.pi * 2 - Double.pi / 2)
    }
    private func percent(_ seconds: Double) -> String {
        guard total > 0 else { return "0%" }
        let value = seconds / total * 100
        return value < 1 && value > 0 ? "<1%" : String(format: "%.0f%%", value)
    }
}

private struct ShareSector: Shape {
    let start: Double
    let end: Double
    let hole: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
        if hole == 0 { path.addLine(to: center) }
        else { path.addArc(center: center, radius: radius * hole, startAngle: .degrees(end * 360 - 90), endAngle: .degrees(start * 360 - 90), clockwise: true) }
        path.closeSubpath()
        return path
    }
}

struct FocusLargeDailyBars: View {
    let buckets: [FocusBucket]
    let color: Color
    let week: Bool
    @Binding var selected: Date?
    var body: some View {
        GeometryReader { geometry in
            let peak = max(1, buckets.map(\.seconds).max() ?? 0)
            let width = max(52, (geometry.size.width - 12) / Double(max(1, buckets.count)))
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(buckets) { bucket in
                        Button { selected = bucket.start } label: {
                            VStack(spacing: 10) {
                                Text(bucket.start > Date() ? "—" : shortDuration(bucket.seconds)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 5).fill(color.opacity(selected == bucket.start ? 1 : 0.75))
                                    .frame(width: min(48, width * 0.62), height: bucket.seconds == 0 ? 2 : max(2, (geometry.size.height - 75) * bucket.seconds / peak))
                                Text(label(bucket)).font(.caption2).foregroundStyle(.secondary)
                            }.frame(width: width, height: max(60, geometry.size.height - 14), alignment: .bottom)
                        }.buttonStyle(.plain).help("\(bucket.start.formatted(date: .complete, time: .omitted)) · \(duration(bucket.seconds))")
                    }
                }
            }
        }
    }
    private func label(_ bucket: FocusBucket) -> String {
        if week { return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: bucket.start) - 1] }
        return bucket.start.formatted(.dateTime.month().day())
    }
    private func shortDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

#if os(macOS)
/// Label bounds are tested against the actual sector, including the ring hole.
struct ShareLabelGeometry {
    static func fits(_ rect: CGRect, start: Double, end: Double, radius: Double, hole: Double) -> Bool {
        let box = rect.insetBy(dx: -2, dy: -2)
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
        guard corners.allSatisfy({ hypot($0.x, $0.y) <= radius }) else { return false }
        let nearestX = max(box.minX, min(0, box.maxX)), nearestY = max(box.minY, min(0, box.maxY))
        guard hypot(nearestX, nearestY) >= radius * hole else { return false }
        if end - start >= 0.999999 { return true }
        let turn = Double.pi * 2, span = (end - start) * turn
        guard corners.allSatisfy({ point in
            var delta = (atan2(point.y, point.x) + .pi / 2 - start * turn).truncatingRemainder(dividingBy: turn)
            if delta < 0 { delta += turn }
            return delta <= span
        }) else { return false }
        // A large sector is non-convex: reject a label crossing either radial boundary.
        for boundary in [start, end] {
            let angle = boundary * turn - .pi / 2
            let dx = cos(angle), dy = sin(angle)
            var lo = radius * hole, hi = radius
            for (direction, lower, upper) in [(dx, box.minX, box.maxX), (dy, box.minY, box.maxY)] {
                if abs(direction) < 0.000001 { if lower < 0 && upper > 0 { continue }; hi = -1; break }
                let a = lower / direction, b = upper / direction
                lo = max(lo, min(a, b)); hi = min(hi, max(a, b))
            }
            if hi > lo + 0.001 { return false }
        }
        return true
    }
}

private struct ShareLabelPlacement {
    let rect: CGRect
    let font: Double
    let inside: Bool
}

private struct MacFocusShareDiagram: View {
    let slices: [FocusShareSlice]
    let total: Double
    let activityCount: Int
    let pie: Bool
    let color: (FocusBreakdown) -> Color
    @Environment(\.colorScheme) private var scheme
    private var background: Color { Color(nsColor: .windowBackgroundColor) }
    private func percent(_ seconds: Double) -> String {
        let value = total > 0 ? seconds / total * 100 : 0
        return value > 0 && value < 1 ? "<1%" : String(format: "%.0f%%", value)
    }
    private func range(_ index: Int) -> (start: Double, end: Double) {
        let start = slices.prefix(index).reduce(0) { $0 + $1.seconds } / max(total, 0.001)
        return (start, start + slices[index].seconds / max(total, 0.001))
    }
    private func angle(_ index: Int) -> Double {
        let r = range(index)
        return (r.start + r.end) * .pi - .pi / 2
    }
    private func textSize(_ name: String, width: Double, font: Double) -> CGSize? {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        let measured = (name as NSString).boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: font), .paragraphStyle: style])
        guard measured.height <= ceil(font * 2.5) else { return nil }
        return CGSize(width: width, height: ceil(measured.height) + ceil(font * 1.3) + 2)
    }
    private func placements(diameter: Double, bounds: CGSize, center: CGPoint) -> [ShareLabelPlacement] {
        let radius = diameter / 2
        var result: [ShareLabelPlacement?] = Array(repeating: nil, count: slices.count)
        for index in slices.indices {
            let r = range(index)
            search: for font in [12.0, 11, 10] {
                let natural = ceil((slices[index].name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: font)]).width)
                let number = ceil((percent(slices[index].seconds) as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: font, weight: .semibold)]).width) + 2
                for width in [max(number, natural + 2), 100, 80, 64, 48, 36].filter({ $0 >= number && $0 <= max(36, diameter * 0.7) }) {
                    guard let size = textSize(slices[index].name, width: width, font: font) else { continue }
                    for fraction in [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8, 0.1, 0.9] {
                        let a = (r.start + (r.end - r.start) * fraction) * .pi * 2 - .pi / 2
                        for depth in (pie ? [0.60, 0.70, 0.80, 0.50, 0.40, 0.85] : [0.85, 0.82, 0.88, 0.79, 0.91, 0.84, 0.86]) {
                            let box = CGRect(x: cos(a) * radius * depth - size.width / 2, y: sin(a) * radius * depth - size.height / 2, width: size.width, height: size.height)
                            if ShareLabelGeometry.fits(box, start: r.start, end: r.end, radius: radius, hole: pie ? 0 : 0.70) {
                                result[index] = ShareLabelPlacement(rect: box.offsetBy(dx: center.x, dy: center.y), font: font, inside: true)
                                break search
                            }
                        }
                    }
                }
            }
        }
        for right in [false, true] {
            let outside = slices.indices.filter { result[$0] == nil && (cos(angle($0)) >= 0) == right }.sorted { sin(angle($0)) < sin(angle($1)) }
            let gap = min(48, max(1, (bounds.height - 12) / Double(max(1, outside.count))))
            var ys: [Double] = []
            for index in outside {
                let natural = center.y + sin(angle(index)) * radius
                ys.append(max(gap / 2 + 6, max(natural, (ys.last ?? -gap) + gap)))
            }
            if let last = ys.last, last > bounds.height - gap / 2 - 6 {
                let shift = last - (bounds.height - gap / 2 - 6)
                ys = ys.map { $0 - shift }
            }
            for (rank, index) in outside.enumerated() {
                result[index] = ShareLabelPlacement(rect: CGRect(x: right ? bounds.width - 90 : 2, y: ys[rank] - 21, width: 88, height: 42), font: 11, inside: false)
            }
        }
        return result.compactMap { $0 }
    }
    private func layout(in bounds: CGSize) -> (diameter: Double, center: CGPoint, labels: [ShareLabelPlacement]) {
        var left = 0.0, right = 0.0
        var diameter = 1.0, center = CGPoint.zero
        var labels: [ShareLabelPlacement] = []
        // Reserve a gutter only on the side that actually needs external labels.
        // A smaller circle can expose another outside label, so settle both sides.
        for _ in 0..<3 {
            diameter = max(1, min(bounds.height - 16, bounds.width - left - right - 24))
            center = CGPoint(x: left + (bounds.width - left - right) / 2, y: bounds.height / 2)
            labels = placements(diameter: diameter, bounds: bounds, center: center)
            let nextLeft = labels.indices.contains { !labels[$0].inside && cos(angle($0)) < 0 } ? 96.0 : left
            let nextRight = labels.indices.contains { !labels[$0].inside && cos(angle($0)) >= 0 } ? 96.0 : right
            if nextLeft == left && nextRight == right { break }
            left = nextLeft; right = nextRight
        }
        return (diameter, center, labels)
    }
    private func rgb(_ color: Color) -> (Double, Double, Double) {
        var resolved: NSColor?
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.deviceRGB)
        }
        guard let resolved else { return (0.5, 0.5, 0.5) }
        return (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
    }
    private func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return linear(rgb.0) * 0.2126 + linear(rgb.1) * 0.7152 + linear(rgb.2) * 0.0722
    }
    private func ink(_ fill: Color, inside: Bool) -> Color {
        let base = rgb(fill)
        if inside { return luminance(base) > 0.179 ? .black : .white }
        let bg = luminance(rgb(background)), target = scheme == .dark ? 1.0 : 0.0
        for step in 0...20 {
            let amount = Double(step) / 20
            let adjusted = (base.0 * (1 - amount) + target * amount, base.1 * (1 - amount) + target * amount, base.2 * (1 - amount) + target * amount)
            let light = luminance(adjusted)
            if (max(bg, light) + 0.05) / (min(bg, light) + 0.05) >= 4.5 {
                return Color(red: adjusted.0, green: adjusted.1, blue: adjusted.2)
            }
        }
        return scheme == .dark ? .white : .black
    }
    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.size
            let layout = layout(in: bounds)
            let size = layout.diameter, center = layout.center, labels = layout.labels
            ZStack {
                Circle().fill(Color.secondary.opacity(0.08)).frame(width: size, height: size).position(center)
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    let r = range(index), fill = slice.source.map(color) ?? Color.gray
                    ShareSector(start: r.start, end: r.end, hole: pie ? 0 : 0.70)
                        .fill(fill).frame(width: size, height: size).position(center)
                        .help("\(slice.name) · \(duration(slice.seconds)) · \(percent(slice.seconds))")
                    let placement = labels[index], textColor = ink(fill, inside: placement.inside)
                    if !placement.inside {
                        let a = angle(index), right = cos(a) >= 0
                        Path { path in
                            path.move(to: CGPoint(x: center.x + cos(a) * size / 2, y: center.y + sin(a) * size / 2))
                            path.addLine(to: CGPoint(x: center.x + cos(a) * (size / 2 + 7), y: center.y + sin(a) * (size / 2 + 7)))
                            path.addLine(to: CGPoint(x: right ? placement.rect.minX - 3 : placement.rect.maxX + 3, y: placement.rect.midY))
                        }.stroke(textColor, lineWidth: 1)
                    }
                    VStack(spacing: 2) {
                        Text(slice.name).lineLimit(2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text(percent(slice.seconds)).fontWeight(.semibold).monospacedDigit().fixedSize()
                    }.font(.system(size: placement.font)).foregroundStyle(textColor)
                        .frame(width: placement.rect.width, height: placement.rect.height)
                        .position(x: placement.rect.midX, y: placement.rect.midY)
                        .help("\(slice.name) · \(percent(slice.seconds)) · \(duration(slice.seconds))")
                        .accessibilityLabel("\(slice.name)，\(percent(slice.seconds))，\(duration(slice.seconds))")
                }
                if !pie || total == 0 {
                    if !pie { Circle().fill(background).frame(width: size * 0.70, height: size * 0.70).position(center) }
                    VStack(spacing: 6) {
                        Text("\(activityCount) 个活动").font(.caption).foregroundStyle(.secondary)
                        Text(duration(total)).font(.system(size: size > 190 ? 22 : 15, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("总有效时长").font(.caption2).foregroundStyle(.secondary)
                    }.position(center).allowsHitTesting(false)
                }
            }
        }
    }
}
#endif
