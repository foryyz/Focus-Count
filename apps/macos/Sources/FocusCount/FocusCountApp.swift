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
    @StateObject private var focusWindow = FocusWindow()
    @State private var chromeVisible = true
    @State private var interaction = Date()
    @State private var pointerLocation: CGPoint?
    @State private var encouragement = 0
    private let greetings = [
        ("🌱 One small start. One meaningful step.", "You don’t have to finish it all. Just begin."),
        ("✨ Make a little room for what matters.", "One thing at a time. You’ve got this."),
        ("☀️ Your next chapter starts here.", "Take a breath. Give this moment your attention."),
        ("🚀 Start small. Stay curious.", "A little focus can take you a long way.")
    ]
    private var phase: Int { store.database.draft.isRunning ? 1 : store.database.draft.startedAt == nil ? 0 : 2 }
    private var ink: Color { colorScheme == .dark ? Color(red: 0.92, green: 0.94, blue: 0.95) : Color(red: 0.12, green: 0.16, blue: 0.20) }
    private var backdrop: Color { colorScheme == .dark ? Color(red: 0.065, green: 0.08, blue: 0.10) : Color(red: 0.975, green: 0.97, blue: 0.955) }
    private var visible: Bool { chromeVisible || !focusWindow.fullScreen || phase != 1 || !command.isEmpty || showData || showHistory || cancellingTimer || store.error != nil }
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
                    Button { focusWindow.toggle(); revealControls() } label: {
                        Image(systemName: focusWindow.fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 32, height: 28)
                    }.help(focusWindow.fullScreen ? "退出全屏" : "进入全屏")
                        .accessibilityLabel(focusWindow.fullScreen ? "退出全屏" : "进入全屏")
                    Menu {
                        Button("专注记录") { showHistory = true }
                        Button("数据管理") { showData = true }
                    } label: { Image(systemName: "ellipsis").frame(width: 30, height: 28) }
                        .menuStyle(.borderlessButton).fixedSize().help("记录与数据")
                }.buttonStyle(.plain)
                    .opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
                Spacer(minLength: 24)
                Group {
                    if phase == 0 {
                        VStack(spacing: 20) {
                            Text("A MOMENT FOR YOURSELF").font(.system(size: 10, weight: .medium)).tracking(3).foregroundStyle(.secondary)
                            Text(greetings[encouragement].0)
                                .font(.system(size: wide ? 38 : 27, weight: .medium, design: .rounded))
                                .multilineTextAlignment(.center).foregroundStyle(ink)
                            Text(greetings[encouragement].1).font(.system(size: wide ? 17 : 14)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            HStack {
                                TextField("这次想专注于什么？（可选）", text: $subject)
                                    .textFieldStyle(.plain).onSubmit { toggleTimer() }
                                    .accessibilityLabel("本次活动名称，可选")
                                if !store.subjects.isEmpty {
                                    Menu { ForEach(store.subjects, id: \.self) { item in Button(item) { subject = item } } }
                                    label: { Image(systemName: "clock.arrow.circlepath") }
                                        .menuStyle(.borderlessButton).fixedSize().help("最近活动")
                                }
                            }.padding(12).frame(maxWidth: 330)
                                .background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            Button { toggleTimer() } label: {
                                Label("开始专注", systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .padding(.horizontal, 26).padding(.vertical, 14)
                                    .foregroundStyle(.white)
                                    .background(Color(red: 0.08, green: 0.40, blue: 0.36), in: Capsule())
                            }.buttonStyle(.plain).disabled(store.blocked)
                            Text("按回车开始 · 不必等到准备完美").font(.caption).foregroundStyle(.secondary)
                        }.transition(.opacity)
                    } else {
                        VStack(spacing: wide ? 26 : 16) {
                            HStack(spacing: 8) {
                                Circle().fill(phase == 1 ? Color.teal : .orange).frame(width: 6, height: 6)
                                Text(phase == 1 ? "IN FOCUS" : "ON A BREAK").tracking(3)
                            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            Text(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "留给眼前这一件事" : subject)
                                .font(.system(size: wide ? 22 : 16, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                            Button { toggleTimer() } label: {
                                timerDigits(size: min(180, min(geometry.size.width * 0.12, geometry.size.height * 0.23)))
                            }.buttonStyle(.plain).disabled(store.blocked)
                                .accessibilityLabel("专注时间 " + duration(store.database.draft.seconds()))
                                .accessibilityHint(phase == 1 ? "暂停计时" : "继续计时")
                            FocusFlow(running: phase == 1, reduceMotion: reduceMotion)
                                .frame(maxWidth: wide ? 460 : 300)
                            Text(phase == 1 ? "Stay with this moment. 🌊" : "Take a breath. Come back when you’re ready. 🍃")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }.transition(.opacity)
                    }
                }.frame(maxWidth: .infinity)
                Spacer(minLength: 24)
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        TextField("!stop 结束 · !sex 标记", text: $command)
                            .textFieldStyle(.plain).font(.system(size: 12))
                            .padding(12).frame(maxWidth: 300)
                            .background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            .focused($commandFocused).onSubmit { submit() }
                        if phase != 0 {
                            Button { toggleTimer() } label: {
                                Label(phase == 1 ? "暂停" : "继续", systemImage: phase == 1 ? "pause" : "play")
                            }
                            Button("结束") { store.finish() }
                            Menu {
                                Button("取消本次计时", role: .destructive) { cancellingTimer = true }
                            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                        }
                        Spacer(minLength: 0)
                        if !focusWindow.fullScreen {
                            Button { showHistory = true } label: { Label("专注记录", systemImage: "chart.bar.xaxis") }
                        }
                    }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.blocked)
                    Text("FULL ATTENTION. ONE THING AT A TIME.").font(.system(size: 9)).tracking(2).foregroundStyle(.tertiary)
                }.frame(maxWidth: 900).opacity(visible ? 1 : 0).allowsHitTesting(visible).accessibilityHidden(!visible)
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
        .frame(minWidth: 720, minHeight: 520)
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
                    command = ""; subject = ""; hint = ""; encouragement = (encouragement + 1) % greetings.count; commandFocused = true
                }
            }
        } message: { Text("本次未保存的计时将被清除，不生成专注记录。已有专注记录不会受到影响。") }
        .onAppear { commandFocused = true }
        .sheet(isPresented: $showData, onDismiss: { commandFocused = true }) { DataExchangeView(store: store) }
        .sheet(isPresented: $showHistory, onDismiss: { commandFocused = true }) { HistoryView(store: store) }
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
                    Button("返回计时") { store.resumeEditingTimer(); commandFocused = true }
                    Spacer()
                    Button("保存记录") {
                        let completed = duration(store.database.draft.seconds())
                        if store.save(subject: subject, focus: focus) {
                            subject = ""; command = ""; commandFocused = true
                            encouragement = (encouragement + 1) % greetings.count
                            hint = "✨ " + completed + " of focus. Well done. Take a little break."
                        }
                    }.keyboardShortcut(.defaultAction)
                        .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(28).frame(width: 420).interactiveDismissDisabled()
        }
    }
    private func revealControls() { chromeVisible = true; interaction = Date() }
    private func toggleTimer() { store.toggle(); commandFocused = true; revealControls() }
    private func timerDigits(size: CGFloat) -> some View {
        let parts = duration(store.database.draft.seconds()).split(separator: ":")
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(String(parts[0]) + ":" + String(parts[1]))
                .font(.system(size: size, weight: .medium, design: .monospaced)).foregroundStyle(ink)
            Text(":" + String(parts[2]))
                .font(.system(size: size * 0.57, weight: .regular, design: .monospaced)).foregroundStyle(.secondary)
        }.lineLimit(1).minimumScaleFactor(0.5)
    }
    private func submit() {
        let value = FocusCommand(command)
        if value == .toggle { toggleTimer(); hint = "" }
        else if value == .stop { store.finish(); command = ""; hint = "" }
        else if value == .sex {
            if store.markEvent() { command = ""; hint = "已标记 SEX · " + Date().formatted(date: .omitted, time: .standard) }
        }
        else { hint = "!stop 结束专注；!sex 标记一次；空输入回车开始或暂停。" }
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
            .defaultSize(width: 880, height: 580)
            .windowResizability(.contentMinSize)
    }
}
