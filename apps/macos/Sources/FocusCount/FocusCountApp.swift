import SwiftUI
import AppKit

@MainActor final class StudyStore: ObservableObject {
    @Published var database = Database()
    @Published var error: String?
    @Published var blocked = false
    private var ticker: Timer?
    private var ticks = 0
    private var observers: [NSObjectProtocol] = []
    private var file: URL { get throws { try Storage.directory.appendingPathComponent("sessions.json") } }

    init() {
        do {
            try Storage.migrateLegacyData(from: Storage.legacyDirectory, to: Storage.directory)
            if try FileManager.default.fileExists(atPath: file.path) {
                database = try JSONDecoder().decode(Database.self, from: Data(contentsOf: file))
                guard database.version == 1 else { throw CocoaError(.fileReadUnknown) }
            }
        } catch {
            blocked = true
            self.error = "无法读取数据，已停止写入以保护原文件。请检查数据目录：\(error.localizedDescription)"
        }
        if !blocked {
            do { try writeCSV() } catch { self.error = "CSV 更新失败：\(error.localizedDescription)" }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.objectWillChange.send()
                self.ticks += 1
                if self.ticks % 20 == 0 && self.database.draft.isRunning { self.persist() }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persist() }
        })
    }
    func persist() {
        guard !blocked else { return }
        do {
            try FileManager.default.createDirectory(at: Storage.directory, withIntermediateDirectories: true)
            var snapshot = database
            snapshot.draft = database.draft.checkpoint()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: file, options: .atomic)
        } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    func writeCSV() throws {
        try FileManager.default.createDirectory(at: Storage.directory, withIntermediateDirectories: true)
        try Data(Storage.csv(database.sessions).utf8).write(to: Storage.directory.appendingPathComponent("sessions.csv"), options: .atomic)
    }
    func toggle() {
        guard !blocked, database.pendingEnd == nil else { return }
        database.draft.toggle()
        persist()
    }
    func pause() { database.draft.pause(); persist() }
    func finish() {
        guard !blocked, database.draft.startedAt != nil else { return }
        database.draft.pause()
        database.pendingEnd = Date()
        persist()
    }
    func resumeEditingTimer() { database.pendingEnd = nil; persist() }
    func save(subject: String, focus: String) -> Bool {
        guard !blocked, let start = database.draft.startedAt, let end = database.pendingEnd else { return false }
        let old = database
        database.sessions.append(StudySession(startedAt: start, endedAt: end, activeSeconds: database.draft.seconds(), subject: subject.trimmingCharacters(in: .whitespacesAndNewlines), focus: focus))
        database.draft = TimerState()
        database.pendingEnd = nil
        error = nil
        persist()
        if error != nil { database = old; return false }
        do { try writeCSV() } catch { self.error = "记录已保存，但 CSV 更新失败：\(error.localizedDescription)" }
        return true
    }
}

func duration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
}

struct ContentView: View {
    @StateObject private var store = StudyStore()
    @State private var command = ""
    @State private var subject = ""
    @State private var focus = "A"
    @State private var hint = ""
    @FocusState private var commandFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var phase: Int { store.database.draft.isRunning ? 1 : store.database.draft.startedAt == nil ? 0 : 2 }
    private var stateColor: Color {
        let dark = colorScheme == .dark
        switch phase {
        case 1: return dark ? Color(red: 0.36, green: 0.85, blue: 0.65) : Color(red: 0.08, green: 0.43, blue: 0.31)
        case 2: return dark ? Color(red: 0.96, green: 0.73, blue: 0.35) : Color(red: 0.57, green: 0.34, blue: 0.08)
        default: return dark ? Color(red: 0.64, green: 0.73, blue: 0.86) : Color(red: 0.34, green: 0.43, blue: 0.56)
        }
    }
    private var stateTitle: String { phase == 1 ? "正在学习" : phase == 2 ? "休息一下 · 已暂停" : "准备好，开始专注" }
    private var stateIcon: String { phase == 1 ? "leaf.fill" : phase == 2 ? "pause.circle.fill" : "play.circle.fill" }
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("FocusCount").font(.title2.bold())
                Spacer()
                Button {
                    do { NSWorkspace.shared.open(try Storage.directory) }
                    catch { store.error = error.localizedDescription }
                } label: { Image(systemName: "folder") }
                    .help("打开 JSON 和 CSV 数据目录")
            }
            Button { store.toggle(); commandFocused = true } label: {
                VStack(spacing: 18) {
                    Label(stateTitle, systemImage: stateIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(stateColor.opacity(0.10), in: Capsule())
                    Text(duration(store.database.draft.seconds()))
                        .font(.system(size: 58, weight: .light, design: .monospaced))
                    HStack(spacing: 7) {
                        Image(systemName: phase == 1 ? "pause.fill" : "play.fill").font(.caption)
                        Text(phase == 1 ? "点击或回车暂停 · 专注时间正在累积" : phase == 2 ? "点击或回车继续 · 暂停不计时" : "点击或回车开始本次学习")
                            .font(.callout)
                    }
                }
                .foregroundStyle(stateColor)
                .frame(maxWidth: .infinity).padding(.vertical, 26)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(colors: [stateColor.opacity(colorScheme == .dark ? 0.20 : 0.12), stateColor.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(stateColor.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(store.blocked)
            .accessibilityLabel("\(stateTitle)，\(duration(store.database.draft.seconds()))")
            .accessibilityHint(phase == 1 ? "暂停计时" : "开始或继续计时")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: phase)
            HStack {
                TextField("输入 stop! 并回车，结束本次学习", text: $command)
                    .textFieldStyle(.roundedBorder).focused($commandFocused)
                    .onSubmit { submit() }
                Button { store.finish() } label: {
                    Label("结束", systemImage: "stop.circle.fill")
                }
                .tint(.orange)
                .disabled(store.database.draft.startedAt == nil || store.blocked)
            }
            if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Text("学习记录").font(.headline)
                Spacer()
                Text("共 \(store.database.sessions.count) 次 · \(duration(store.database.sessions.reduce(0) { $0 + $1.activeSeconds }))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.database.sessions.isEmpty {
                Text("完成第一次学习后，记录会显示在这里。")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
            } else {
                List(store.database.sessions.reversed()) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.subject).font(.headline)
                            Text(s.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(duration(s.activeSeconds)).monospacedDigit()
                        Text(s.focus).font(.headline).frame(width: 30).padding(5)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }.padding(.vertical, 4)
                }.listStyle(.inset).frame(minHeight: 130)
            }
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            Text("自动保存在项目 data 目录 · JSON + CSV").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(28).frame(minWidth: 540, minHeight: 530)
        .onAppear { commandFocused = true }
        .sheet(isPresented: Binding(get: { store.database.pendingEnd != nil }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("完成本次学习", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold()).foregroundStyle(.teal)
                Text("有效学习时间  \(duration(store.database.draft.seconds()))").foregroundStyle(.secondary)
                TextField("学习科目（必填）", text: $subject).textFieldStyle(.roundedBorder)
                Picker("专注度", selection: $focus) {
                    ForEach(["S", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                Text("S 最高 · D 最低，按本次学习的主观感受选择。").font(.caption).foregroundStyle(.secondary)
                if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
                HStack {
                    Button("返回计时") { store.resumeEditingTimer(); commandFocused = true }
                    Spacer()
                    Button("保存记录") {
                        if store.save(subject: subject, focus: focus) { subject = ""; command = ""; commandFocused = true }
                    }.keyboardShortcut(.defaultAction)
                        .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(28).frame(width: 420).interactiveDismissDisabled()
        }
    }
    private func submit() {
        let value = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { store.toggle(); hint = "" }
        else if value == "stop!" { store.finish(); command = ""; hint = "" }
        else { hint = "结束请输入 stop!；开始或暂停请清空输入后按回车。" }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct FocusCountApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("FocusCount · 学习计时", id: "main") { ContentView() }
            .defaultSize(width: 580, height: 650)
    }
}
