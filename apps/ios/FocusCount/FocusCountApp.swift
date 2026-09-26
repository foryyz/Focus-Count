import SwiftUI
import FocusCountCore

@main struct FocusCountPhoneApp: App {
    @StateObject private var store = PhoneStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup { TimerScreen(store: store).tint(.teal) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { store.checkpoint() }
            }
    }
}

struct TimerScreen: View {
    @ObservedObject var store: PhoneStore
    @State private var history = false
    @State private var exchange = false
    @State private var today = false
    @State private var targetSettings = false
    @State private var markers = false
    @State private var analysis = false
    @StateObject private var appearance = FocusAppearanceStore()
    @StateObject private var targetCountdown: TargetCountdownStore
    init(store: PhoneStore) {
        self.store = store
        _targetCountdown = StateObject(wrappedValue: TargetCountdownStore(snapshot: store.state.goal, writer: { store.updateGoal($0) }))
    }
    @State private var cancelling = false
    @State private var subject = ""
    @State private var command = ""
    @State private var markerInput = false
    @State private var message = ""
    @State private var immersive = false
    @FocusState private var markerFocused: Bool
    @FocusState private var activityFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private static let greetings = [
        ("🌱 One small start. One meaningful step.", "You don’t have to finish it all. Just begin."),
        ("✨ Make a little room for what matters.", "One thing at a time. You’ve got this."),
        ("☀️ Your next chapter starts here.", "Take a breath. Give this moment your attention."),
        ("🚀 Start small. Stay curious.", "A little focus can take you a long way."),
        ("✨ Begin before you feel ready.", "Tap start. You don’t have to be perfect.")
    ]
    @State private var encouragement = Int.random(in: 0..<5)
    private var running: Bool { store.state.clock.isRunning }
    private var idle: Bool { store.state.clock.startedAt == nil }
    private var ink: Color { scheme == .dark ? Color(red: 0.92, green: 0.94, blue: 0.95) : Color(red: 0.12, green: 0.16, blue: 0.20) }
    private var pauseInk: Color { scheme == .dark ? Color(red: 0.91, green: 0.72, blue: 0.43) : Color(red: 0.53, green: 0.34, blue: 0.13) }
    private var backdrop: Color { scheme == .dark ? Color(red: 0.065, green: 0.08, blue: 0.10) : Color(red: 0.975, green: 0.97, blue: 0.955) }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 24)
                        if idle { welcome }
                        else { timer(width: geometry.size.width) }
                        Spacer(minLength: 24)
                        if !idle { controls }
                        if !message.isEmpty {
                            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
                    }.padding(.horizontal, 24).padding(.vertical, 24)
                        .frame(maxWidth: 640).frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            }
            .background(backdrop.ignoresSafeArea())
            .navigationTitle(immersive ? "" : "🧠 FOCUS-COUNT").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !immersive {
                        Menu {
                            Button { history = true } label: { Label("专注记录", systemImage: "list.bullet.rectangle") }
                            Button { analysis = true } label: { Label("专注分析", systemImage: "chart.bar.xaxis") }
                            Button { markers = true } label: { Label("时间标记", systemImage: "tag") }
                            Button { targetSettings = true } label: { Label("目标日期", systemImage: "calendar") }
                            Button { exchange = true } label: { Label("数据管理", systemImage: "arrow.up.arrow.down") }
                        } label: { Image(systemName: "square.grid.2x2") }.accessibilityLabel("记录、分析与设置")
                    }
                    Button { immersive.toggle(); activityFocused = false; markerFocused = false } label: {
                        Image(systemName: immersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }.accessibilityLabel(immersive ? "退出沉浸模式" : "沉浸模式")
                }
            }
            .safeAreaInset(edge: .bottom, alignment: .leading) {
                if idle && !immersive {
                    Button { today = true } label: {
                        Image(systemName: "sun.max").frame(width: 44, height: 44)
                            .background(ink.opacity(0.05), in: Circle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("今日概览")
                        .padding(.leading, 24).padding(.bottom, 8)
                }
            }
            .statusBarHidden(immersive)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: running)
            .onChange(of: idle) { _, value in
                if value {
                    subject = ""; markerInput = false; command = ""
                    encouragement = Self.greetings.indices.filter { $0 != encouragement }.randomElement() ?? 0
                }
            }
            .task(id: message) {
                guard !message.isEmpty else { return }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                message = ""
            }
            .alert("取消本次计时？", isPresented: $cancelling) {
                Button("保留计时", role: .cancel) {}
                Button("取消并归零", role: .destructive) { store.cancelTimer() }
            } message: { Text("清除本次未保存的计时，不生成记录。已有记录不受影响。") }
            .sheet(isPresented: $history) { PhoneHistory(store: store) }
            .sheet(isPresented: $markers) { PhoneEventHistory(store: store) }
            .sheet(isPresented: $analysis) { PhoneFocusAnalysis(store: store, appearance: appearance) }
            .sheet(isPresented: $today) { PhoneTodaySheet(store: store, appearance: appearance) }
            .sheet(isPresented: $targetSettings) { PhoneTargetSettings(store: targetCountdown) }
            .onChange(of: store.state.goal) { _, value in targetCountdown.receive(value) }
            .sheet(isPresented: $exchange) { ExchangeScreen(store: store) }
            .sheet(isPresented: Binding(get: { store.state.clock.pendingEnd != nil && !exchange && !history && !analysis && !markers && !today && !targetSettings }, set: { _ in })) {
                if let start = store.state.clock.startedAt, let end = store.state.clock.pendingEnd {
                    RecordEditor(store: store, session: StudySession(startedAt: start, endedAt: end, activeSeconds: store.state.clock.seconds(), subject: store.state.activity ?? "", focus: "A"), completesTimer: true) {
                        message = "✨ A little focus, a meaningful step. Well done."
                    }
                }
            }
        }
    }
    private var welcome: some View {
        VStack(spacing: 28) {
            TargetCountdownRow(store: targetCountdown) { targetSettings = true }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let minutes = Int(store.today(at: context.date).seconds) / 60
                VStack(spacing: 12) {
                    Text("Today’s focus").font(.system(.title3, design: .rounded, weight: .medium)).foregroundStyle(.secondary)
                    (Text("\(minutes / 60)H").font(.system(size: 64, weight: .medium, design: .rounded))
                     + Text("  \(minutes % 60)m").font(.system(size: 30, weight: .regular, design: .rounded)).foregroundColor(.secondary))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(Self.greetings[encouragement].1).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            HStack {
                TextField("这次想专注于什么？（可选）", text: $subject)
                    .font(.body).focused($activityFocused).submitLabel(.go)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { startOrMark() }
                    .accessibilityHint("输入活动名称开始专注，或输入 !文字添加标记")
                if !store.subjects.isEmpty {
                    Menu {
                        ForEach(store.subjects, id: \.self) { name in Button(name) { subject = name } }
                    } label: { Image(systemName: "clock.arrow.circlepath").frame(minWidth: 36, minHeight: 44) }
                        .accessibilityLabel("最近活动")
                }
            }.padding(.horizontal, 14).frame(minHeight: 52)
                .background(ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            Button { startOrMark() } label: {
                Label("开始专注", systemImage: "play.fill").font(.headline)
            }.buttonStyle(PrismaticStartStyle()).disabled(store.blocked)
        }
    }
    private func timer(width: CGFloat) -> some View {
        VStack(spacing: 22) {
            Label(running ? "IN FOCUS" : "已暂停 · PAUSED", systemImage: running ? "circle.fill" : "pause.fill")
                .font(.caption.weight(.semibold)).tracking(2)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(running ? .teal : pauseInk)
                .background((running ? Color.teal : pauseInk).opacity(0.09), in: Capsule())
            if let activity = store.state.activity, !activity.isEmpty {
                Text(activity).font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button { store.toggle() } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let parts = phoneDuration(store.state.clock.seconds(at: context.date)).split(separator: ":")
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(parts.prefix(2).joined(separator: ":"))
                            .font(.system(size: min(100, width * 0.17), weight: running ? .regular : .light, design: .monospaced))
                            .foregroundStyle(running ? ink : pauseInk)
                        Text(":" + String(parts.last ?? "00"))
                            .font(.system(size: min(56, width * 0.095), weight: .light, design: .monospaced))
                            .foregroundStyle(running ? Color.secondary : pauseInk.opacity(0.7))
                    }.lineLimit(1).minimumScaleFactor(0.5)
                }
            }.buttonStyle(.plain).disabled(store.blocked)
                .accessibilityLabel((running ? "正在专注，" : "已暂停，") + phoneDuration(store.state.clock.seconds()))
                .accessibilityHint(running ? "轻点暂停" : "轻点继续")
            FocusFlow(running: running && scenePhase == .active, reduceMotion: reduceMotion, tint: running ? .teal : pauseInk)
                .frame(maxWidth: 300)
            Text(running ? "Stay with this moment. 🌊" : "Take a breath. Come back when you’re ready. 🍃")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
    private var controls: some View {
        VStack(spacing: 16) {
            if markerInput {
                HStack {
                    TextField("!文字，例如 !sad", text: $command)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($markerFocused).submitLabel(.send).onSubmit { submitMarker() }
                    Button { submitMarker() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("保存标记")
                }.padding(.leading, 14).background(ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { actionButtons }
                VStack(spacing: 8) { actionButtons }
            }.font(.subheadline).buttonStyle(.plain).foregroundStyle(.secondary)
        }.disabled(store.blocked)
    }
    @ViewBuilder private var actionButtons: some View {
        Button { store.toggle() } label: { Label(running ? "暂停" : "继续", systemImage: running ? "pause" : "play").fixedSize().frame(minHeight: 44) }
        Button { markerInput.toggle(); markerFocused = markerInput } label: { Label("标记", systemImage: "ellipsis.circle").fixedSize().frame(minHeight: 44) }
        Button { cancelling = true } label: { Label("取消", systemImage: "xmark.circle").fixedSize().frame(minHeight: 44) }
        Button { markerFocused = false; store.finish() } label: { Label("结束", systemImage: "stop.circle").fixedSize().frame(minHeight: 44) }
    }
    private func startOrMark() {
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("!") {
            if store.markCommand(subject) { message = "已标记 " + markerName(subject); subject = ""; activityFocused = false }
        } else if store.start(activity: subject) { activityFocused = false; message = "" }
    }
    private func submitMarker() {
        if store.markCommand(command) {
            message = "已标记 " + markerName(command)
            command = ""; markerInput = false; markerFocused = false
        }
    }
    private func markerName(_ input: String) -> String {
        String(input.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Ambient waves communicate a running timer, not progress toward a target.
struct FocusFlow: View {
    let running: Bool
    let reduceMotion: Bool
    var tint: Color = .teal
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !running || reduceMotion)) { context in
            Canvas { canvas, size in
                let t = running && !reduceMotion ? context.date.timeIntervalSinceReferenceDate : 0
                for line in 0..<3 {
                    var path = Path()
                    for step in 0...100 {
                        let x = size.width * Double(step) / 100
                        let envelope = sin(Double(step) / 100 * .pi)
                        let y = size.height / 2 + sin(Double(step) / 100 * .pi * 3 - t * 0.65 + Double(line) * 0.8) * 14 * envelope
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    canvas.stroke(path, with: .color(tint.opacity(running ? 0.48 - Double(line) * 0.12 : 0.32 - Double(line) * 0.07)), lineWidth: line == 0 ? 2 : 1)
                }
            }
        }.frame(height: 54).accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// A compact foil-like finish; the label stays still and readable as light passes behind it.
struct PrismaticStartStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var hovering = false
    private let colors = [
        Color(red: 0.12, green: 0.48, blue: 0.57),
        Color(red: 0.25, green: 0.39, blue: 0.75),
        Color(red: 0.53, green: 0.32, blue: 0.72),
        Color(red: 0.69, green: 0.32, blue: 0.49),
        Color(red: 0.64, green: 0.43, blue: 0.20)
    ]
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 32).padding(.vertical, 15)
            .foregroundStyle(.white)
            .background {
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !isEnabled || scenePhase != .active)) { context in
                    let progress = reduceMotion || !isEnabled ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay {
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * 0.55)
                                    .rotationEffect(.degrees(20))
                                    .offset(x: geometry.size.width * (progress * 2.2 - 0.7))
                            }.clipShape(Capsule())
                        }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.15), .white.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: colors[2].opacity(isEnabled ? (hovering ? 0.28 : 0.17) : 0), radius: hovering ? 13 : 9, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovering)
            .onHover { hovering = $0 }
    }
}
