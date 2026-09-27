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
            Button(action: adjust) { Label("调整微休息参数与声音", systemImage: "slider.horizontal.3") }
                .buttonStyle(.plain).font(.callout).padding(8)
        }.padding(16).frame(width: 300)
    }
}

struct FocusModeSettingsView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings = FocusRoutineSettings()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: FocusMode.microBreak.symbol).foregroundStyle(.teal)
                Text("微休息设置").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("提醒节奏").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Stepper("随机间隔下限：\(settings.minimumMinutes) 分钟", value: $settings.minimumMinutes, in: 1...180)
                    Stepper("随机间隔上限：\(settings.maximumMinutes) 分钟", value: $settings.maximumMinutes, in: 1...180)
                    Stepper("微休息：\(settings.microSeconds) 秒", value: $settings.microSeconds, in: 1...300)
                    Divider()
                    Text("专注与长休息").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Stepper("每轮专注：\(settings.roundMinutes) 分钟", value: $settings.roundMinutes, in: 1...360)
                    Stepper("长休息：\(settings.restMinutes) 分钟", value: $settings.restMinutes, in: 1...180)
                    HStack { Text("音量"); Slider(value: $settings.volume, in: 0...1); Button("试听") { store.previewModeSound(volume: settings.volume) } }
                    if !settings.isValid { Text("随机间隔上限不能小于下限。").font(.caption).foregroundStyle(.red) }
                    Text("每轮包含微休息；所有休息均不计入专注时长。长休息结束需手动继续。休眠或重启后暂停，需手动恢复。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("参数在下一轮生效。保存设置不会切换当前模式。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            Divider()
            HStack {
                Button("恢复默认参数") { settings = FocusRoutineSettings() }
                Spacer()
                Button("应用") {
                    settings.mode = store.modeSettings.mode
                    if store.setMode(settings) { dismiss() }
                }.disabled(!settings.isValid || store.blocked || store.database.pendingEnd != nil)
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 440, height: 480)
            .onAppear { settings = store.modeSettings }
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
                    Button("跳过这次休息") { store.skipModeRest() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
