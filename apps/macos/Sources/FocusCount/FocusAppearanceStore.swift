import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor final class FocusAppearanceStore: ObservableObject {
    @Published private(set) var settings: FocusAppearance
    @Published var error: String?
    private let defaults: UserDefaults
    private let key = "focus-analysis-appearance-v1"
    private var readable = true
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { settings = try JSONDecoder().decode(FocusAppearance.self, from: data) }
            catch { settings = FocusAppearance(); readable = false; self.error = "分类设置无法读取，已保留原设置，暂停修改。" }
        } else { settings = FocusAppearance() }
    }
    private func change(_ edit: (inout FocusAppearance) -> Void) {
        guard readable else { return }
        var next = settings; edit(&next)
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: key)
            settings = next; error = nil
        } catch { self.error = "无法保存分类设置：\(error.localizedDescription)" }
    }
    @discardableResult func addCategory(_ input: String) -> Bool {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validName(name), readable else { return false }
        change { $0.categories.append(FocusCategory(name: name)) }
        return true
    }
    private func validName(_ name: String, excluding id: UUID? = nil) -> Bool {
        guard !name.isEmpty, name != "未分类", !settings.categories.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            error = "分类名称不能为空、重复或使用“未分类”。"; return false
        }
        return true
    }
    func rename(_ id: UUID, to input: String) {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validName(name, excluding: id) else { return }
        change { if let i = $0.categories.firstIndex(where: { $0.id == id }) { $0.categories[i].name = name } }
    }
    func remove(_ id: UUID) {
        change { value in value.categories.removeAll { $0.id == id }; value.assignments = value.assignments.filter { $0.value != id } }
    }
    func assign(_ activity: String, to category: UUID?) {
        guard category == nil || settings.categories.contains(where: { $0.id == category }) else { return }
        change { $0.assignments[activity] = category }
    }
    func categoryID(_ activity: String) -> UUID? {
        guard let id = settings.assignments[activity], settings.categories.contains(where: { $0.id == id }) else { return nil }
        return id
    }
    func category(_ activity: String) -> String {
        settings.categories.first { $0.id == categoryID(activity) }?.name ?? "未分类"
    }
    func ensureColors(_ activities: [String]) {
        let names = activities.map { "activity:" + $0 } + settings.categories.map { "category:" + $0.id.uuidString } + ["category:none"]
        guard names.contains(where: { settings.colors[$0] == nil }) else { return }
        change { value in
            for name in names.sorted() where value.colors[name] == nil { value.colors[name] = MarkerColors.nextColor(used: Set(value.colors.values)) }
        }
    }
    func categoryKey(_ activity: String) -> String { "category:" + (categoryID(activity)?.uuidString ?? "none") }
    func color(_ key: String) -> Color {
        let value = UInt32(settings.colors[key] ?? "249E91", radix: 16) ?? 0x249E91
        return Color(red: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255, blue: Double(value & 255) / 255)
    }
    func setColor(_ color: Color, key: String) {
        #if os(macOS)
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let hex = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
        let hex = String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        #endif
        change { $0.colors[key] = hex }
    }
}
