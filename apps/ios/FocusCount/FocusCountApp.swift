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
    @State private var events = false
    @State private var cancelling = false
    @Environment(\.colorScheme) private var scheme
    private var color: Color { store.state.clock.isRunning ? .teal : store.state.clock.startedAt == nil ? .secondary : .orange }
    private var title: String { store.state.clock.isRunning ? "正在专注" : store.state.clock.startedAt == nil ? "从此刻开始" : "休息一下 · 已暂停" }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 16)
                        Button { store.toggle() } label: {
                            VStack(spacing: 24) {
                                Label(title, systemImage: store.state.clock.isRunning ? "leaf" : "circle.dotted")
                                    .font(.subheadline.weight(.medium))
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(phoneDuration(store.state.clock.seconds(at: context.date)))
                                        .font(.system(size: 64, weight: .light, design: .monospaced))
                                        .minimumScaleFactor(0.45).lineLimit(1)
                                }
                                Text(store.state.clock.isRunning ? "轻点暂停" : store.state.clock.startedAt == nil ? "轻点开始" : "轻点继续")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 32).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(color).disabled(store.blocked)
                            .accessibilityLabel("\(title)，\(phoneDuration(store.state.clock.seconds()))")
                        if store.state.clock.startedAt != nil {
                            Button { store.finish() } label: {
                                Label("结束本次专注", systemImage: "stop.circle")
                                    .font(.subheadline.weight(.medium)).padding(.horizontal, 20).padding(.vertical, 12)
                            }.buttonStyle(.bordered).clipShape(Capsule()).disabled(store.blocked)
                            Button("取消计时") { cancelling = true }
                                .font(.footnote).foregroundStyle(.secondary).disabled(store.blocked)
                        }
                        Spacer(minLength: 24)
                        if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
                        VStack(spacing: 20) {
                            Button { history = true } label: { Label("专注记录", systemImage: "chart.bar.xaxis").font(.subheadline) }
                            Button { events = true } label: { Label("时间标记", systemImage: "mappin.circle").font(.subheadline) }
                            Text("锁屏也会继续计时\n把注意力留给眼前的事")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                        }.padding(.bottom, 24)
                    }.padding(.horizontal, 28).frame(minHeight: geometry.size.height)
                }.scrollIndicators(.hidden)
            }
            .background(LinearGradient(colors: [Color.teal.opacity(scheme == .dark ? 0.12 : 0.06), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
            .navigationTitle("FocusCount").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { exchange = true } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("数据导入与导出") } }
            .alert("取消本次计时？", isPresented: $cancelling) {
                Button("保留计时", role: .cancel) {}
                Button("取消并归零", role: .destructive) { store.cancelTimer() }
            } message: { Text("清除本次未保存的计时，不生成记录。已有记录不受影响。") }
            .sheet(isPresented: $events) { PhoneEventHistory(store: store) }
            .sheet(isPresented: $history) { PhoneHistory(store: store) }
            .sheet(isPresented: $exchange) { ExchangeScreen(store: store) }
            .sheet(isPresented: Binding(get: { store.state.clock.pendingEnd != nil }, set: { _ in })) {
                if let start = store.state.clock.startedAt, let end = store.state.clock.pendingEnd {
                    RecordEditor(store: store, session: StudySession(startedAt: start, endedAt: end, activeSeconds: store.state.clock.seconds(), subject: "", focus: "A"), completesTimer: true)
                }
            }
        }
    }
}
