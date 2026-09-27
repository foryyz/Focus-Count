import SwiftUI
import FocusCountCore

struct FocusModeSettingsView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings = FocusRoutineSettings()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("专注模式").font(.headline); Spacer(); Button("关闭") { dismiss() } }
            Picker("模式", selection: $settings.mode) {
                Text("普通专注").tag(FocusMode.standard)
                Text("微休息").tag(FocusMode.microBreak)
            }.pickerStyle(.segmented)
            if settings.mode == .microBreak {
                Text("随机提醒你闭眼休息，再回到眼前的事情。").font(.callout).foregroundStyle(.secondary)
                Stepper("随机间隔下限：\(settings.minimumMinutes) 分钟", value: $settings.minimumMinutes, in: 1...180)
                Stepper("随机间隔上限：\(settings.maximumMinutes) 分钟", value: $settings.maximumMinutes, in: 1...180)
                Stepper("微休息：\(settings.microSeconds) 秒", value: $settings.microSeconds, in: 1...300)
                Stepper("每轮专注：\(settings.roundMinutes) 分钟", value: $settings.roundMinutes, in: 1...360)
                Stepper("长休息：\(settings.restMinutes) 分钟", value: $settings.restMinutes, in: 1...180)
                HStack { Text("音量"); Slider(value: $settings.volume, in: 0...1); Button("试听") { store.previewModeSound(volume: settings.volume) } }
                if !settings.isValid { Text("随机间隔上限不能小于下限。").font(.caption).foregroundStyle(.red) }
                Text("每轮包含微休息；所有休息均不计入专注时长。长休息结束需手动继续。休眠或重启后暂停，需手动恢复。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.database.draft.startedAt != nil {
                Text("切换模式立即生效；调整参数在下一轮生效。切换模式将重新开始一轮，已累计专注时长保留。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("恢复默认参数") { let mode = settings.mode; settings = FocusRoutineSettings(); settings.mode = mode }
                Spacer()
                Button("应用") { if store.setMode(settings) { dismiss() } }
                    .disabled(!settings.isValid || store.blocked || store.database.pendingEnd != nil)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 370)
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
