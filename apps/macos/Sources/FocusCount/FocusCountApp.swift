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
    @State private var showMarkerInput = false
    @State private var subject = ""
    @State private var focus = "A"
    @State private var hint = ""
    @State private var showHistory = false
    @State private var showData = false
    @State private var cancellingTimer = false
    @FocusState private var commandFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var focusWindow = FocusWindow()
    @State private var chromeVisible = true
    @State private var interaction = Date()
    @State private var pointerLocation: CGPoint?
    @State private var encouragement = Int.random(in: 0..<5)
    private let greetings = [
        ("🌱 One small start. One meaningful step.", "You don’t have to finish it all. Just begin."),
        ("✨ Make a little room for what matters.", "One thing at a time. You’ve got this."),
        ("☀️ Your next chapter starts here.", "Take a breath. Give this moment your attention."),
        ("🚀 Start small. Stay curious.", "A little focus can take you a long way."),
        ("✨ Begin before you feel ready.", "Press Return to start. You don’t have to be perfect.")
    ]
    private var phase: Int { store.database.draft.isRunning ? 1 : store.database.draft.startedAt == nil ? 0 : 2 }
    private var ink: Color { colorScheme == .dark ? Color(red: 0.92, green: 0.94, blue: 0.95) : Color(red: 0.12, green: 0.16, blue: 0.20) }
    private var pauseInk: Color { colorScheme == .dark ? Color(red: 0.91, green: 0.72, blue: 0.43) : Color(red: 0.53, green: 0.34, blue: 0.13) }
    private var backdrop: Color { colorScheme == .dark ? Color(red: 0.065, green: 0.08, blue: 0.10) : Color(red: 0.975, green: 0.97, blue: 0.955) }
    private var visible: Bool { chromeVisible || !focusWindow.fullScreen || phase != 1 || showMarkerInput || !command.isEmpty || showData || showHistory || cancellingTimer || store.error != nil }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 1000
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.teal)
                        Text("FOCUSCOUNT").font(.system(size: 11, weight: .semibold)).tracking(2.5)
                    }.foregroundStyle(.secondary)
                    Spacer()
                    Button { showHistory = true } label: {
                        Image(systemName: "chart.bar.xaxis").frame(width: 32, height: 28)
                    }.help("专注记录").accessibilityLabel("专注记录")
                    Button { showData = true } label: {
                        Image(systemName: "arrow.up.arrow.down").frame(width: 32, height: 28)
                    }.help("数据管理").accessibilityLabel("数据管理")
                    Button { focusWindow.toggle(); revealControls() } label: {
                        Image(systemName: focusWindow.fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 32, height: 28)
                    }.help(focusWindow.fullScreen ? "退出全屏" : "进入全屏")
                        .accessibilityLabel(focusWindow.fullScreen ? "退出全屏" : "进入全屏")
                }.buttonStyle(.plain)
                    .opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
                Spacer(minLength: 24)
                Group {
                    if phase == 0 {
                        VStack(spacing: 28) {
                            VStack(spacing: 12) {
                            Text(greetings[encouragement].0)
                                .font(.system(size: min(44, max(30, geometry.size.width * 0.037)), weight: .medium, design: .rounded))
                                .multilineTextAlignment(.center).foregroundStyle(ink)
                            Text(greetings[encouragement].1).font(.system(size: wide ? 19 : 16)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            }.frame(maxWidth: 760).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                TextField("这次想专注于什么？（可选）", text: $subject)
                                    .textFieldStyle(.plain).onSubmit { submitActivity() }.help("填写活动开始专注，或输入 !文字并回车添加标记")
                                    .accessibilityLabel("本次活动名称，可选")
                                if !store.subjects.isEmpty {
                                    Menu { ForEach(store.subjects, id: \.self) { item in Button(item) { subject = item } } }
                                    label: { Image(systemName: "clock.arrow.circlepath") }
                                        .menuStyle(.borderlessButton).fixedSize().help("最近活动")
                                }
                            }.font(.system(size: 15)).padding(14).frame(maxWidth: 360)
                                .background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            Button { submitActivity() } label: {
                                Label("开始专注", systemImage: "play.fill")
                                    .font(.system(size: 17, weight: .semibold))
                            }.buttonStyle(PrismaticStartStyle()).disabled(store.blocked).keyboardShortcut(.defaultAction)
                        }.transition(.opacity)
                    } else {
                        VStack(spacing: wide ? 26 : 16) {
                            HStack(spacing: 8) {
                                Image(systemName: phase == 1 ? "circle.fill" : "pause.fill")
                                    .font(.system(size: phase == 1 ? 6 : 11, weight: .bold))
                                Text(phase == 1 ? "IN FOCUS" : "已暂停 · PAUSED").tracking(2)
                            }.font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(phase == 1 ? Color.teal : pauseInk)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background((phase == 1 ? Color.teal : pauseInk).opacity(0.09), in: Capsule())
                            if !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(subject)
                                    .font(.system(size: wide ? 22 : 16, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Button { toggleTimer() } label: {
                                timerDigits(size: min(180, min(geometry.size.width * 0.12, geometry.size.height * 0.23)))
                            }.buttonStyle(.plain).disabled(store.blocked).keyboardShortcut(.defaultAction)
                                .accessibilityLabel((phase == 1 ? "正在专注，" : "已暂停，") + duration(store.database.draft.seconds()))
                                .accessibilityHint(phase == 1 ? "暂停计时" : "继续计时")
                            FocusFlow(running: phase == 1, reduceMotion: reduceMotion, tint: phase == 1 ? .teal : pauseInk)
                                .frame(maxWidth: wide ? 460 : 300)
                            Text(phase == 1 ? "Stay with this moment. 🌊" : "Take a breath. Come back when you’re ready. 🍃")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }.transition(.opacity)
                    }
                }.frame(maxWidth: .infinity)
                Spacer(minLength: 24)
                if phase != 0 {
                    VStack(spacing: 12) {
                        if showMarkerInput {
                            TextField("!文字 标记，例如 !sad", text: $command)
                                .textFieldStyle(.plain).font(.system(size: 12))
                                .padding(10).frame(maxWidth: 280)
                                .background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                                .focused($commandFocused).onSubmit { submit() }
                                .task { commandFocused = true }
                                .onExitCommand { showMarkerInput = false; commandFocused = false }
                        }
                        HStack(spacing: 24) {
                            Button { toggleTimer() } label: {
                                Label(phase == 1 ? "暂停" : "继续", systemImage: phase == 1 ? "pause" : "play")
                            }
                            Button {
                                showMarkerInput.toggle()
                                commandFocused = showMarkerInput
                                revealControls()
                            } label: { Label("标记", systemImage: "ellipsis.circle") }
                                .help(showMarkerInput ? "收起标记输入框" : "添加时间标记")
                            Button { cancellingTimer = true } label: {
                                Label("取消", systemImage: "xmark.circle")
                            }.help("取消本次计时，不保存记录")
                            Button { store.finish() } label: {
                                Label("结束", systemImage: "stop.circle")
                            }.help("结束本次专注并保存记录")
                        }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.blocked)
                    }.frame(maxWidth: 900).opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
                }
                if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary).padding(.top, 10) }
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(.top, 8) }
            }
            .padding(.horizontal, wide ? 64 : 32).padding(.top, 22).padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backdrop.ignoresSafeArea())
            .background(FocusWindowReader(controller: focusWindow))
            .onContinuousHover { hover in
                if case .active(let location) = hover, pointerLocation != location {
                    pointerLocation = location
                    revealControls()
                }
            }
        }
        .frame(minWidth: 720, minHeight: phase == 0 ? 440 : 520)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: visible)
        .onChange(of: focusWindow.fullScreen) { _ in revealControls() }
        .onChange(of: phase) { _ in revealControls() }
        .onChange(of: command) { _ in revealControls() }
        .task(id: interaction) {
            guard focusWindow.fullScreen, phase == 1 else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            chromeVisible = false
        }
        .task(id: hint) {
            guard !hint.isEmpty else { return }
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            hint = ""
        }
        .alert("取消本次计时？", isPresented: $cancellingTimer) {
            Button("保留计时", role: .cancel) {}
            Button("取消并归零", role: .destructive) {
                if store.cancelTimer() {
                    command = ""; subject = ""; hint = ""; showMarkerInput = false; encouragement = greetings.indices.filter { $0 != encouragement }.randomElement() ?? 0; commandFocused = showMarkerInput
                }
            }
        } message: { Text("本次未保存的计时将被清除，不生成专注记录。已有专注记录不会受到影响。") }
        .onAppear { commandFocused = showMarkerInput }
        .sheet(isPresented: $showData, onDismiss: { commandFocused = showMarkerInput }) { DataExchangeView(store: store) }
        .sheet(isPresented: $showHistory, onDismiss: { commandFocused = showMarkerInput }) { HistoryView(store: store) }
        .sheet(isPresented: Binding(get: { store.database.pendingEnd != nil }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("完成本次专注", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold()).foregroundStyle(.teal)
                Text("有效专注时间  \(duration(store.database.draft.seconds()))").foregroundStyle(.secondary)
                TextField("活动名称（必填）", text: $subject).textFieldStyle(.roundedBorder)
                if !store.subjects.isEmpty {
                    Menu("选择已有活动") {
                        ForEach(store.subjects, id: \.self) { item in Button(item) { subject = item } }
                    }.fixedSize()
                }
                Picker("专注度", selection: $focus) {
                    ForEach(["S", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                Text("S 最高 · D 最低，按本次专注的主观感受选择。").font(.caption).foregroundStyle(.secondary)
                if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
                HStack {
                    Button("返回计时") { store.resumeEditingTimer(); commandFocused = showMarkerInput }
                    Spacer()
                    Button("保存记录") {
                        let completed = duration(store.database.draft.seconds())
                        if store.save(subject: subject, focus: focus) {
                            subject = ""; command = ""; showMarkerInput = false; commandFocused = false
                            encouragement = greetings.indices.filter { $0 != encouragement }.randomElement() ?? 0
                            hint = "✨ " + completed + " of focus. Well done. Take a little break."
                        }
                    }.keyboardShortcut(.defaultAction)
                        .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(28).frame(width: 420).interactiveDismissDisabled()
        }
    }
    private func revealControls() { chromeVisible = true; interaction = Date() }
    private func toggleTimer() { store.toggle(); commandFocused = showMarkerInput; revealControls() }
    private func timerDigits(size: CGFloat) -> some View {
        let parts = duration(store.database.draft.seconds()).split(separator: ":")
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(String(parts[0]) + ":" + String(parts[1]))
                .font(.system(size: size, weight: phase == 1 ? .medium : .light, design: .monospaced)).foregroundStyle(phase == 1 ? ink : pauseInk)
            Text(":" + String(parts[2]))
                .font(.system(size: size * 0.57, weight: phase == 1 ? .regular : .light, design: .monospaced)).foregroundStyle(phase == 1 ? Color.secondary : pauseInk.opacity(0.75))
        }.lineLimit(1).minimumScaleFactor(0.5)
    }
    private func submitActivity() {
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("!") {
            if saveMarker(subject) { subject = "" }
        } else { toggleTimer() }
    }
    @discardableResult private func saveMarker(_ input: String) -> Bool {
        guard case .mark(let label) = FocusCommand(input) else {
            hint = "输入 ! 加标记文字，例如 !sex、!sad。"
            return false
        }
        let time = Date()
        guard store.markEvent(kind: label, at: time) else { return false }
        hint = "已标记 " + label + " · " + time.formatted(date: .omitted, time: .standard)
        return true
    }
    private func submit() {
        if saveMarker(command) {
            command = ""
            showMarkerInput = false
            commandFocused = false
        }
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
        Window("FocusCount · 专注计时", id: "main") { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 920, height: 560)
            .windowResizability(.contentMinSize)
    }
}
