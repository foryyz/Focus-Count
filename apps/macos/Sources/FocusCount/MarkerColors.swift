import SwiftUI
import AppKit

/// Local presentation preferences, separate from exchanged event data.
@MainActor final class MarkerColors: ObservableObject {
    @Published private(set) var values: [String: String]
    private let defaults: UserDefaults
    private let key = "marker-colors-v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
    func ensure(_ names: [String]) {
        var next = values
        for name in names where next[name] == nil { next[name] = Self.nextColor(used: Set(next.values)) }
        guard next != values else { return }
        values = next; defaults.set(next, forKey: key)
    }
    static func nextColor(used: Set<String>) -> String {
        let palette = ["249E91", "627AD5", "BA65B8", "DC8B39", "CC5C79", "77A745", "419CCA", "A985CF", "A88556", "C0A536", "508B72", "AF6E4E"]
        if let available = palette.first(where: { !used.contains($0) }) { return available }
        // Extend the palette with evenly distributed hues before reusing any exact color.
        for index in 0..<360 {
            let color = NSColor(calibratedHue: (Double(index) * 0.61803398875).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.75, alpha: 1)
            let hex = encode(color)
            if !used.contains(hex) { return hex }
        }
        return palette[used.count % palette.count]
    }
    func color(_ name: String) -> Color {
        let hex = UInt32(values[name] ?? "249E91", radix: 16) ?? 0x249E91
        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    func set(_ color: Color, for name: String) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        values[name] = Self.encode(rgb); defaults.set(values, forKey: key)
    }
    private static func encode(_ color: NSColor) -> String {
        String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
