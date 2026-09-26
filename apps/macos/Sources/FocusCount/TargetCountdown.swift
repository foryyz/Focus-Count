import SwiftUI
import FocusCountCore

struct TargetDate: Codable, Equatable {
    var name: String
    var emoji: String
    var date: Date
    var includesTime: Bool
    var hidden: Bool

    func deadline(calendar: Calendar = .current) -> Date {
        includesTime ? date : calendar.startOfDay(for: date)
    }

    func remaining(now: Date, calendar: Calendar = .current, totalHours: Bool = false) -> String {
        let target = deadline(calendar: calendar)
        if now < target {
            if totalHours {
                let hours = Int(target.timeIntervalSince(now) / 3600)
                return hours == 0 ? "不足 1 小时" : "还有 \(hours) 小时"
            }
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
    @Published private(set) var error: String?
    @Published private(set) var totalHours: Bool
    private let defaults: UserDefaults
    private let key = "focus-target-date-v1"
    private let hiddenKey = "focus-target-hidden-v1"
    private var snapshot: GoalSnapshot?
    private let writer: ((GoalSnapshot) -> Bool)?

    init(defaults: UserDefaults = .standard, snapshot: GoalSnapshot? = nil, writer: ((GoalSnapshot) -> Bool)? = nil) {
        self.defaults = defaults; self.writer = writer
        self.totalHours = defaults.bool(forKey: "focus-target-total-hours-v1")
        let old = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(TargetDate.self, from: $0) }
        if let snapshot { receive(snapshot) }
        else if let old {
            target = old
            if defaults.object(forKey: hiddenKey) == nil { defaults.set(old.hidden, forKey: hiddenKey) }
            if writer != nil { _ = save(old) }
        }
    }
    func receive(_ value: GoalSnapshot?) {
        snapshot = value
        guard let value, !value.deleted else { target = nil; return }
        // First imports remain hidden until explicitly made visible on this device.
        let hidden = defaults.object(forKey: hiddenKey) == nil ? true : defaults.bool(forKey: hiddenKey)
        target = TargetDate(name: value.name, emoji: value.emoji, date: value.date, includesTime: value.includesTime, hidden: hidden)
    }
    @discardableResult func save(_ value: TargetDate) -> Bool {
        let now = max(Date(), (snapshot?.updatedAt ?? .distantPast).addingTimeInterval(0.001))
        let unchanged = snapshot.map { !$0.deleted && $0.name == value.name && $0.emoji == value.emoji && $0.date == value.date && $0.includesTime == value.includesTime } ?? false
        let next = unchanged ? snapshot! : GoalSnapshot(name: value.name, emoji: value.emoji, date: value.date, includesTime: value.includesTime, updatedAt: now)
        if !unchanged, let writer, !writer(next) { error = "保存失败，目标未修改。"; return false }
        guard let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: key); defaults.set(value.hidden, forKey: hiddenKey)
        snapshot = next; target = value; error = nil
        return true
    }
    func setTotalHours(_ value: Bool) {
        totalHours = value
        defaults.set(value, forKey: "focus-target-total-hours-v1")
    }
    func hide() { setHidden(true) }
    func setHidden(_ hidden: Bool) {
        guard var value = target else { return }
        value.hidden = hidden
        defaults.set(hidden, forKey: hiddenKey)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        target = value
    }
    @discardableResult func remove() -> Bool {
        let next = GoalSnapshot(name: "", date: Date(), deleted: true,
            updatedAt: max(Date(), (snapshot?.updatedAt ?? .distantPast).addingTimeInterval(0.001)))
        if let writer, !writer(next) { error = "删除失败，目标未修改。"; return false }
        defaults.removeObject(forKey: key)
        snapshot = next; target = nil; error = nil
        return true
    }
}

struct TargetCountdownRow: View {
    @ObservedObject var store: TargetCountdownStore
    var edit: () -> Void

    private var hideButtonSize: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }
    var body: some View {
        if let target = store.target {
            if !target.hidden {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 10) {
                        Button(action: edit) {
                            HStack(spacing: 8) {
                                if !target.emoji.isEmpty { Text(target.emoji) }
                                Text(target.name).lineLimit(1).truncationMode(.tail)
                                Text(target.remaining(now: context.date, totalHours: store.totalHours)).fontWeight(.medium).fixedSize()
                            }
                        }.buttonStyle(.plain).help("编辑目标日期")
                        #if os(iOS)
                        Button { store.hide() } label: {
                            Image(systemName: "eye.slash").frame(width: hideButtonSize, height: hideButtonSize)
                        }.buttonStyle(.plain).help("隐藏目标与倒数").accessibilityLabel("隐藏目标与倒数")
                        #endif
                    }.font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: 520)
                }
            }
        } else {
            Button(action: edit) { Label("设置目标日期", systemImage: "plus") }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

#if os(macOS)
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
                if let target = store.target {
                    Button {
                        let hidden = !target.hidden
                        store.setHidden(hidden)
                        showOnHome = !hidden
                        revealed = false
                        if !hidden { load() }
                    } label: {
                        Image(systemName: target.hidden ? "eye.slash" : "eye").frame(width: 28, height: 28)
                    }.buttonStyle(.plain)
                        .help(target.hidden ? "显示倒数" : "隐藏倒数")
                        .accessibilityLabel(target.hidden ? "显示倒数" : "隐藏倒数")
                }
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("倒数格式", selection: Binding(get: { store.totalHours }, set: { store.setTotalHours($0) })) {
                Text("天 + 小时").tag(false)
                Text("总小时").tag(true)
            }.pickerStyle(.segmented)
            if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
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
                if store.target == nil { Toggle("在首页显示目标与倒数", isOn: $showOnHome) }
                Text("目标随 JSON 导入导出同步；隐藏状态仅保存在本机。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if store.target != nil {
                        Button("删除目标", role: .destructive) { deleting = true }
                    }
                    Spacer()
                    Button("保存") {
                        if store.save(TargetDate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji, date: date, includesTime: includesTime, hidden: !showOnHome)) { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 390)
            .onAppear { if !concealed { load() } }
            .alert("删除目标日期？", isPresented: $deleting) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { if store.remove() { dismiss() } }
            } message: { Text("不会影响专注记录和时间标记。") }
    }
    private func load() {
        guard let target = store.target else { return }
        name = target.name; emoji = target.emoji; date = target.date
        includesTime = target.includesTime; showOnHome = !target.hidden
    }
}

#endif
