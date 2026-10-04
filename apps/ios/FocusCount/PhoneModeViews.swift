import SwiftUI
import FocusCountCore

extension FocusMode {
    var symbol: String { self == .standard ? "scope" : self == .course ? "graduationcap" : "leaf" }
    var title: String { self == .standard ? "普通专注" : self == .course ? "课程模式" : "微休息" }
}

struct PhoneModeMenu: View {
    @ObservedObject var store: PhoneStore
    var adjust: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("专注模式").font(.headline)
            ForEach(FocusMode.allCases, id: \.self) { mode in
                Button {
                    var settings = store.modeSettings; settings.mode = mode
                    if store.setMode(settings) { dismiss() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: mode.symbol).font(.title2).frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title).font(.headline)
                            Text(mode == .standard ? "按自己的节奏持续专注" : mode == .course ? "定时上课 · 课间休息 · 自动循环" : "随机提醒 · 闭眼休息 · 循环专注")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark").opacity(store.modeSettings.mode == mode ? 1 : 0)
                    }.padding(12).background(store.modeSettings.mode == mode ? Color.teal.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(store.blocked || store.state.clock.pendingEnd != nil)
            }
            Divider()
            Button(action: adjust) { Label("调整模式参数与声音", systemImage: "slider.horizontal.3").frame(minHeight: 44) }
        }.padding(24).presentationDetents([.height(410), .large]).presentationDragIndicator(.visible)
    }
}

struct PhoneModeSettings: View {
    @ObservedObject var store: PhoneStore
    @ObservedObject private var sounds = PhoneSounds.shared
    @Environment(\.dismiss) private var dismiss
    @State private var settings = FocusRoutineSettings()
    @State private var mode: FocusMode = .standard
    @State private var soundSettings = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("模式", selection: $mode) {
                    ForEach(FocusMode.allCases, id: \.self) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
                }.pickerStyle(.segmented).padding()
                Form {
                    if mode == .microBreak {
                        Section("提醒节奏") {
                            Stepper("间隔下限：\(settings.minimumMinutes) 分钟", value: $settings.minimumMinutes, in: 1...180)
                            Stepper("间隔上限：\(settings.maximumMinutes) 分钟", value: $settings.maximumMinutes, in: 1...180)
                            Stepper("微休息：\(settings.microSeconds) 秒", value: $settings.microSeconds, in: 1...300)
                        }
                        Section("专注与长休息") {
                            Stepper("每轮专注：\(settings.roundMinutes) 分钟", value: $settings.roundMinutes, in: 1...360)
                            Stepper("长休息：\(settings.restMinutes) 分钟", value: $settings.restMinutes, in: 1...180)
                        }
                        Section("提示音") {
                            soundPicker("开始休息", id: $settings.restSound, fallback: "Glass")
                            soundPicker("开始专注", id: $settings.focusSound, fallback: "Pop")
                            HStack { Text("前台音量"); Slider(value: Binding(get: { settings.volume(for: mode) }, set: { settings.setVolume($0, for: mode) }), in: 0...1) }
                            Button("管理与导入提示音") { soundSettings = true }
                            if let error = sounds.error { Text(error).foregroundStyle(.red) }
                        }
                        Section {
                            if !settings.isValid { Text("间隔上限不能小于下限。").foregroundStyle(.red) }
                            else if !PhoneRoutine.supports(settings) {
                                Text("为保证整轮后台提醒，请缩短每轮时间或增加间隔下限：每轮分钟数不超过间隔下限的 31 倍。")
                                    .foregroundStyle(.red)
                            }
                            Text("每轮包含微休息，休息不计入专注时长。长休息结束后手动继续下一轮。参数从下一轮生效，保存不会切换当前模式。")
                            Text("锁屏或切到后台仍继续计时，需允许通知。后台提示音由系统音量控制，静音和专注模式可能使声音不响；超过 29 秒的自定义声音在通知中只播放前 29 秒。")
                            Button("恢复默认参数") { settings = settings.restoringDefaults(for: mode) }
                        }.font(.footnote)
                    } else {
                        if mode == .course {
                            Section("课程与课间") {
                                Stepper("一节课：\(settings.lessonMinutes) 分钟", value: $settings.lessonMinutes, in: 1...360)
                                Stepper("课间休息：\(settings.classBreakMinutes) 分钟", value: $settings.classBreakMinutes, in: 1...180)
                            }
                        }
                        Section("提示音") {
                            if mode == .course {
                                soundPicker("上课", id: $settings.classStartSound, fallback: "Pop")
                                soundPicker("下课", id: $settings.classEndSound, fallback: "Glass")
                            } else {
                                soundPicker("开始／继续", id: $settings.startSound, fallback: "Pop")
                                soundPicker("暂停", id: $settings.pauseSound, fallback: "Glass")
                            }
                            HStack { Text("前台音量"); Slider(value: Binding(get: { settings.volume(for: mode) }, set: { settings.setVolume($0, for: mode) }), in: 0...1) }
                            Button("管理与导入提示音") { soundSettings = true }
                            if let error = sounds.error { Text(error).foregroundStyle(.red) }
                        }
                        Section {
                            Text(mode == .course ? "开始时播放上课提示音，下课后进入课间休息，休息结束自动上课。课间不计入专注时长；暂停冻结当前阶段。重新开始课程后使用新参数。" : "开始或继续专注时播放开始提示音，暂停时播放暂停提示音。")
                            if mode == .course {
                                Text("锁屏或切到后台仍计时；需允许通知。后台声音由系统音量控制，静音和专注模式可能使声音不响。每次安排未来 32 节课的提醒，打开应用后补齐。")
                            }
                            Button("恢复默认参数") { settings = settings.restoringDefaults(for: mode) }
                        }.font(.footnote)
                    }
                }
            }.navigationTitle("模式设置").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("应用") {
                            settings.mode = store.modeSettings.mode
                            if store.setMode(settings) { dismiss() }
                        }.disabled(!PhoneRoutine.supports(settings) || store.blocked || store.state.clock.pendingEnd != nil)
                    }
                }
                .onAppear { settings = store.modeSettings; mode = store.modeSettings.mode }
                .onChange(of: sounds.custom.map(\.id)) { _ in
                    for id in settings.soundIDs where !sounds.sounds.contains(where: { $0.id == id }) { settings = settings.removingSound(id) }
                }
                .sheet(isPresented: $soundSettings) { PhoneSoundSettings(store: store) }
        }
    }
    private func soundPicker(_ title: String, id: Binding<String?>, fallback: String) -> some View {
        Group {
            Picker(title, selection: Binding(get: { id.wrappedValue ?? fallback }, set: { id.wrappedValue = $0 })) {
                ForEach(sounds.sounds) { sound in Text(sound.name).tag(sound.id) }
                if let selected = id.wrappedValue, !sounds.sounds.contains(where: { $0.id == selected }) { Text("声音不可用").tag(selected) }
            }
            Button { sounds.play(id.wrappedValue ?? fallback, volume: settings.volume(for: mode)) } label: { Label("试听", systemImage: "play.circle") }
                .buttonStyle(.borderless).font(.subheadline).frame(minHeight: 44)
                .accessibilityLabel("试听" + title + "提示音")
        }
    }
}

struct PhoneRestView: View {
    @ObservedObject var store: PhoneStore
    var body: some View {
        if let plan = store.state.routine {
            VStack(spacing: 22) {
                Text(plan.suspended ? "REST PAUSED" : plan.phase == .microRest ? "REST YOUR EYES" : plan.phase == .ready ? "READY WHEN YOU ARE" : (plan.settings.mode == .course ? "CLASS BREAK" : "TAKE A BREAK"))
                    .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Text(plan.phase == .ready ? "下一轮" : phoneDuration(ceil(plan.remaining)))
                    .font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                FocusFlow(running: false, reduceMotion: true).frame(maxWidth: 300)
                Text(plan.phase == .microRest ? "闭上眼睛，听到下一声提示后继续。" : plan.phase == .ready ? "准备好后，继续下一轮专注。" : "放下手头的事情，休息一下。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("已专注 " + phoneDuration(store.state.clock.seconds())).font(.caption).foregroundStyle(.secondary)
                if plan.phase != .ready {
                    Button { store.skipRest() } label: { Text("跳过这次休息").underline().frame(minHeight: 44) }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
                }
            }
        }
    }
}
