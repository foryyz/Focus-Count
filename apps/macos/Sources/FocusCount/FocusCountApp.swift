import SwiftUI
import AppKit

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
    @State private var showHistory = false
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
            Button { showHistory = true } label: {
                Label("学习记录", systemImage: "chart.bar.xaxis")
                    .font(.callout).foregroundStyle(.secondary)
            }.buttonStyle(.plain).padding(.top, 4)
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(28).frame(minWidth: 540, minHeight: 370)
        .onAppear { commandFocused = true }
        .sheet(isPresented: $showHistory) { HistoryView(store: store) }
        .sheet(isPresented: Binding(get: { store.database.pendingEnd != nil }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("完成本次学习", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold()).foregroundStyle(.teal)
                Text("有效学习时间  \(duration(store.database.draft.seconds()))").foregroundStyle(.secondary)
                TextField("学习科目（必填）", text: $subject).textFieldStyle(.roundedBorder)
                if !store.subjects.isEmpty {
                    Menu("选择已有科目") {
                        ForEach(store.subjects, id: \.self) { item in Button(item) { subject = item } }
                    }.fixedSize()
                }
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
            .defaultSize(width: 580, height: 410)
    }
}
