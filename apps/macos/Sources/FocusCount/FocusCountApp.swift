import FocusCountCore
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
    @State private var showData = false
    @State private var cancellingTimer = false
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
        VStack(spacing: 16) {
            HStack {
                Text("FocusCount")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showData = true } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 28, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("数据导入、导出与历史版本").accessibilityLabel("数据管理")
            }
            Button { store.toggle(); commandFocused = true } label: {
                VStack(spacing: 14) {
                    Label(stateTitle, systemImage: stateIcon)
                        .font(.system(size: 13, weight: .medium))
                    Text(duration(store.database.draft.seconds()))
                        .font(.system(size: 84, weight: .light, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(phase == 1 ? "点击或回车暂停" : phase == 2 ? "点击或回车继续" : "点击或回车开始")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .foregroundStyle(stateColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(store.blocked)
            .accessibilityLabel("\(stateTitle)，\(duration(store.database.draft.seconds()))")
            .accessibilityHint(phase == 1 ? "暂停计时" : "开始或继续计时")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: phase)
            HStack(spacing: 12) {
                TextField("输入 stop! 结束学习", text: $command)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    .focused($commandFocused).onSubmit { submit() }
                Button { store.finish() } label: {
                    Image(systemName: "stop.circle").font(.system(size: 20))
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("结束本次学习").accessibilityLabel("结束本次学习")
                .disabled(store.database.draft.startedAt == nil || store.blocked)
                if store.database.draft.startedAt != nil {
                    Button("取消计时") { cancellingTimer = true }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                        .help("放弃本次计时并归零，不生成记录").disabled(store.blocked)
                }
                Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1, height: 18)
                Button { showHistory = true } label: {
                    Label("学习记录", systemImage: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .medium)).padding(.vertical, 8)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary) }
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .lineLimit(2).help(error)
            }
        }
        .padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 28)
        .frame(width: 800, height: 400)
        .background {
            LinearGradient(
                colors: [stateColor.opacity(colorScheme == .dark ? 0.16 : 0.09), stateColor.opacity(0.025)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()
        }
        .alert("取消本次计时？", isPresented: $cancellingTimer) {
            Button("保留计时", role: .cancel) {}
            Button("取消并归零", role: .destructive) {
                if store.cancelTimer() {
                    command = ""; subject = ""; hint = ""; commandFocused = true
                }
            }
        } message: { Text("本次未保存的计时将被清除，不生成学习记录。已有学习记录不会受到影响。") }
        .onAppear { commandFocused = true }
        .sheet(isPresented: $showData, onDismiss: { commandFocused = true }) { DataExchangeView(store: store) }
        .sheet(isPresented: $showHistory, onDismiss: { commandFocused = true }) { HistoryView(store: store) }
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
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 800, height: 400)
            .windowResizability(.contentSize)
    }
}
