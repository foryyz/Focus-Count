import SwiftUI
import FocusCountCore

extension FocusMode {
    var symbol: String { self == .standard ? "scope" : "leaf" }
    var title: String { self == .standard ? "普通专注" : "微休息" }
}

struct FocusModeMenuView: View {
    @ObservedObject var store: StudyStore
    var adjust: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("专注模式").font(.headline).padding(.bottom, 4)
            ForEach(FocusMode.allCases, id: \.self) { mode in
                Button {
                    var settings = store.modeSettings
                    settings.mode = mode
                    if store.setMode(settings) { dismiss() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.symbol).font(.system(size: 19)).frame(width: 26)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title).font(.system(size: 13, weight: .medium))
                            Text(mode == .standard ? "按自己的节奏持续专注" : "随机提醒 · 闭眼休息 · 循环专注")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark").opacity(store.modeSettings.mode == mode ? 1 : 0)
                    }.padding(12).contentShape(Rectangle())
                        .background(store.modeSettings.mode == mode ? Color.teal.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(store.blocked || store.database.pendingEnd != nil)
            }
            Divider()
            Button(action: adjust) { Label("调整模式参数与声音", systemImage: "slider.horizontal.3") }
                .buttonStyle(.plain).font(.callout).padding(8)
        }.padding(16).frame(width: 300)
    }
}

struct FocusModeSettingsView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings = FocusRoutineSettings()
    @State private var selectedMode: FocusMode = .standard
    @ObservedObject private var library = SoundLibrary.shared
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: selectedMode.symbol).foregroundStyle(.teal)
                Text("模式设置").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            Picker("选择要调整的模式", selection: $selectedMode) {
                ForEach(FocusMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if selectedMode == .microBreak {
                        Text("提醒节奏").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Stepper("随机间隔下限：\(settings.minimumMinutes) 分钟", value: $settings.minimumMinutes, in: 1...180)
                        Stepper("随机间隔上限：\(settings.maximumMinutes) 分钟", value: $settings.maximumMinutes, in: 1...180)
                        Stepper("微休息：\(settings.microSeconds) 秒", value: $settings.microSeconds, in: 1...300)
                        Divider()
                        Text("专注与长休息").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Stepper("每轮专注：\(settings.roundMinutes) 分钟", value: $settings.roundMinutes, in: 1...360)
                        Stepper("长休息：\(settings.restMinutes) 分钟", value: $settings.restMinutes, in: 1...180)
                        soundPicker("开始休息", selection: $settings.restSound, fallback: "Glass")
                        soundPicker("开始专注", selection: $settings.focusSound, fallback: "Pop")
                        HStack { Text("音量"); Slider(value: $settings.volume, in: 0...1) }
                        Text("可在主页右上角「设置 → 提示音」导入并命名自己的声音。")
                            .font(.caption).foregroundStyle(.secondary)
                        if !settings.isValid { Text("随机间隔上限不能小于下限。").font(.caption).foregroundStyle(.red) }
                        Text("每轮包含微休息；所有休息均不计入专注时长。长休息结束需手动继续。休眠或重启后暂停，需手动恢复。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("参数在下一轮生效。保存设置不会切换当前模式。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("按自己的节奏专注", systemImage: FocusMode.standard.symbol).font(.headline)
                        Text("普通专注不自动安排休息，也不播放周期提醒，暂时无需调整参数。")
                            .foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
            Divider()
            HStack {
                Button("恢复默认参数") { settings = FocusRoutineSettings() }.disabled(selectedMode == .standard)
                Spacer()
                Button("应用") {
                    settings.mode = store.modeSettings.mode
                    if store.setMode(settings) { dismiss() }
                }.disabled(!settings.isValid || store.blocked || store.database.pendingEnd != nil)
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 440, height: 480)
            .onAppear { settings = store.modeSettings; selectedMode = store.modeSettings.mode }
            .onChange(of: library.custom.map(\.id)) { _ in
                for id in [settings.restSound, settings.focusSound].compactMap({ $0 }) where !library.sounds.contains(where: { $0.id == id }) { settings = settings.removingSound(id) }
            }
    }
    private func soundPicker(_ title: String, selection: Binding<String?>, fallback: String) -> some View {
        HStack {
            Picker(title, selection: Binding(get: { selection.wrappedValue ?? fallback }, set: { selection.wrappedValue = $0 })) {
                ForEach(library.sounds) { sound in Text(sound.name).tag(sound.id) }
                if let id = selection.wrappedValue, !library.sounds.contains(where: { $0.id == id }) {
                    Text("提示音不可用，请重新选择").tag(id)
                }
            }
            Button("试听") { store.previewModeSound(id: selection.wrappedValue ?? fallback, volume: settings.volume) }
        }
    }
}

struct ModeRestView: View {
    @ObservedObject var store: StudyStore
    var body: some View {
        if let routine = store.database.focusRoutine {
            VStack(spacing: 18) {
                Text(routine.suspended ? "REST PAUSED" : routine.phase == .microRest ? "REST YOUR EYES" : routine.phase == .ready ? "READY WHEN YOU ARE" : "TAKE A BREAK")
                    .font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                Text(routine.phase == .ready ? "下一轮" : duration(routine.remaining.rounded(.up)))
                    .font(.system(size: 62, weight: .light, design: .rounded)).monospacedDigit()
                FocusFlow(running: false, reduceMotion: true, tint: .teal).frame(maxWidth: 300)
                Text(routine.phase == .microRest ? "闭上眼睛，听到下一声提示后继续。" : routine.phase == .ready ? "准备好后，继续下一轮专注。" : "放下手头的事情，休息一下。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("已专注 " + duration(store.database.draft.seconds())).font(.caption).foregroundStyle(.secondary)
                if routine.phase != .ready {
                    Button { store.skipModeRest() } label: { Text("跳过这次休息").underline() }
                        .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
