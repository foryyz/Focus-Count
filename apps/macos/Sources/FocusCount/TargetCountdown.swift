import SwiftUI

struct TargetDate: Codable, Equatable {
    var name: String
    var emoji: String
    var date: Date
    var includesTime: Bool
    var hidden: Bool

    func deadline(calendar: Calendar = .current) -> Date {
        includesTime ? date : calendar.startOfDay(for: date)
    }

    func remaining(now: Date, calendar: Calendar = .current) -> String {
        let target = deadline(calendar: calendar)
        if now < target {
            let parts = calendar.dateComponents([.day, .hour], from: now, to: target)
            let days = max(0, parts.day ?? 0), hours = max(0, parts.hour ?? 0)
            return days == 0 && hours == 0 ? "不足 1 小时" : "还有 \(days) 天 \(hours) 小时"
        }
        if calendar.isDate(now, inSameDayAs: target) { return "目标日到了" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: target), to: calendar.startOfDay(for: now)).day ?? 0
        return "已过去 \(max(0, days)) 天"
    }
}

@MainActor final class TargetCountdownStore: ObservableObject {
    @Published private(set) var target: TargetDate?
    private let defaults: UserDefaults
    private let key = "focus-target-date-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        target = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(TargetDate.self, from: $0) }
    }
    func save(_ value: TargetDate) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        target = value
    }
    func hide() {
        guard var value = target else { return }
        value.hidden = true
        save(value)
    }
    func remove() {
        defaults.removeObject(forKey: key)
        target = nil
    }
}

struct TargetCountdownRow: View {
    @ObservedObject var store: TargetCountdownStore
    var edit: () -> Void

    var body: some View {
        if let target = store.target {
            if !target.hidden {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 10) {
                        Button(action: edit) {
                            HStack(spacing: 8) {
                                if !target.emoji.isEmpty { Text(target.emoji) }
                                Text(target.name).lineLimit(1).truncationMode(.tail)
                                Text(target.remaining(now: context.date)).fontWeight(.medium).fixedSize()
                            }
                        }.buttonStyle(.plain).help("编辑目标日期")
                        Button { store.hide() } label: {
                            Image(systemName: "eye.slash").frame(width: 28, height: 28)
                        }.buttonStyle(.plain).help("隐藏目标与倒数").accessibilityLabel("隐藏目标与倒数")
                    }.font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: 520)
                }
            }
        } else {
            Button(action: edit) { Label("设置目标日期", systemImage: "plus") }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct TargetCountdownSettings: View {
    @ObservedObject var store: TargetCountdownStore
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var name = ""
    @State private var emoji = ""
    @State private var date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
    @State private var includesTime = false
    @State private var showOnHome = true
    @State private var deleting = false

    private var concealed: Bool { store.target?.hidden == true && !revealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("目标日期", systemImage: "calendar").font(.title3.weight(.semibold))
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if concealed {
                Label("目标已隐藏", systemImage: "eye.slash").foregroundStyle(.secondary)
                Text("首页不会显示目标名称、日期或倒数。查看设置不会自动恢复首页显示。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("查看并编辑目标") { load(); revealed = true }
            } else {
                TextField("目标名称", text: $name).textFieldStyle(.roundedBorder)
                TextField("Emoji（可选）", text: $emoji).textFieldStyle(.roundedBorder)
                    .onChange(of: emoji) { value in emoji = String(value.prefix(1)) }
                DatePicker("目标日期", selection: $date, displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                Toggle("指定具体时间", isOn: $includesTime)
                if !includesTime {
                    Text("倒数至所选日期的本地时间 00:00。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("在首页显示目标与倒数", isOn: $showOnHome)
                Text("隐藏状态会记住；此目标仅保存在本机，不包含在数据导出中。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if store.target != nil {
                        Button("删除目标", role: .destructive) { deleting = true }
                    }
                    Spacer()
                    Button("保存") {
                        store.save(TargetDate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji, date: date, includesTime: includesTime, hidden: !showOnHome))
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 390)
            .onAppear { if !concealed { load() } }
            .alert("删除目标日期？", isPresented: $deleting) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { store.remove(); dismiss() }
            } message: { Text("不会影响专注记录和时间标记。") }
    }
    private func load() {
        guard let target = store.target else { return }
        name = target.name; emoji = target.emoji; date = target.date
        includesTime = target.includesTime; showOnHome = !target.hidden
    }
}
