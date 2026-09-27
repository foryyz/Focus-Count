import Foundation
import FocusCountCore
import UserNotifications
import UIKit

struct PhoneRoutine: Codable {
    struct Segment: Codable { var phase: FocusRoutine.Phase; var seconds: Double }
    var settings: FocusRoutineSettings
    var segments: [Segment]
    var elapsed = 0.0
    var anchor: Date
    var suspended = false
    init(settings: FocusRoutineSettings, at date: Date = Date()) {
        self.init(routine: FocusRoutine(settings: settings), at: date)
    }
    init(routine: FocusRoutine, at date: Date = Date()) {
        settings = routine.settings; anchor = date; suspended = routine.suspended
        var routine = routine, result: [Segment] = []
        routine.suspended = false
        while routine.phase != .ready {
            let seconds = routine.phase == .longRest ? routine.remaining : min(routine.remaining, routine.roundRemaining)
            if seconds > 0 { result.append(Segment(phase: routine.phase, seconds: seconds)); routine.advance(seconds) }
            else { routine.advance(0.000001) }
        }
        segments = result
    }
    var portable: FocusRoutine {
        var result = FocusRoutine(settings: settings)
        result.phase = phase; result.remaining = remaining; result.roundRemaining = roundRemaining; result.suspended = suspended
        return result
    }
    var total: Double { segments.reduce(0) { $0 + $1.seconds } }
    var phase: FocusRoutine.Phase {
        var end = 0.0
        for segment in segments { end += segment.seconds; if elapsed < end { return segment.phase } }
        return .ready
    }
    var remaining: Double {
        var end = 0.0
        for segment in segments { end += segment.seconds; if elapsed < end { return end - elapsed } }
        return 0
    }
    var roundRemaining: Double { max(0, total - Double(settings.restMinutes * 60) - elapsed) }
    var isValid: Bool {
        settings.isValid && elapsed.isFinite && elapsed >= 0 && elapsed <= total && segments.count <= 800 &&
        segments.allSatisfy { $0.seconds.isFinite && $0.seconds > 0 && $0.phase != .ready } && total <= Double((settings.roundMinutes + settings.restMinutes) * 60) + 0.001
    }
    static func supports(_ settings: FocusRoutineSettings) -> Bool {
        settings.isValid && Int(ceil(Double(settings.roundMinutes) / Double(settings.minimumMinutes))) * 2 + 2 <= 64
    }
    @discardableResult mutating func advance(at date: Date) -> Double {
        defer { anchor = date }
        guard !suspended else { return 0 }
        let end = min(total, elapsed + max(0, date.timeIntervalSince(anchor)))
        var start = 0.0, focused = 0.0
        for segment in segments {
            let stop = start + segment.seconds
            if segment.phase == .focus { focused += max(0, min(end, stop) - max(elapsed, start)) }
            start = stop
        }
        elapsed = end
        return focused
    }
    mutating func skipRest(at date: Date) {
        guard phase == .microRest else { return }
        elapsed += remaining; anchor = date
    }
    struct Reminder { let date: Date; let phase: FocusRoutine.Phase }
    func reminders(at date: Date) -> [Reminder] {
        var copy = self; copy.advance(at: date)
        guard !copy.suspended else { return [] }
        var end = 0.0, result: [Reminder] = []
        for (index, segment) in segments.enumerated() {
            end += segment.seconds
            if end > copy.elapsed {
                result.append(Reminder(date: date.addingTimeInterval(end - copy.elapsed), phase: index + 1 < segments.count ? segments[index + 1].phase : .ready))
            }
        }
        return result
    }
}

@MainActor final class PhoneNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PhoneNotifications()
    private var generation = UUID()
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }
    func replace(_ plan: PhoneRoutine?, report: @escaping (String) -> Void) {
        let token = UUID(); generation = token
        Task {
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Focus reminders")
            defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
            let pending = await center.pendingNotificationRequests()
            guard generation == token else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("focus-mode-") }.map(\.identifier))
            guard let plan, !plan.suspended, plan.phase != .ready else { return }
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard generation == token else { return }
                guard allowed else { report("通知未开启：后台仍会计时，但无法提醒。请在系统设置中允许 FocusCount 通知。"); return }
                let reminders = plan.reminders(at: Date())
                if reminders.count > 64 { report("此轮提醒较多，后台先安排前 64 条；再次打开应用会补齐后续提醒。") }
                for (index, reminder) in reminders.prefix(64).enumerated() {
                    guard generation == token else { return }
                    let content = UNMutableNotificationContent()
                    let rest = reminder.phase == .microRest || reminder.phase == .longRest
                    content.title = reminder.phase == .microRest ? "闭眼休息一下" : reminder.phase == .longRest ? "本轮结束，休息一下" : reminder.phase == .ready ? "休息结束" : "继续专注"
                    content.body = reminder.phase == .microRest ? "休息 \(plan.settings.microSeconds) 秒，下一声提示后继续。" : reminder.phase == .longRest ? "休息 \(plan.settings.restMinutes) 分钟。" : reminder.phase == .ready ? "准备好后打开 FocusCount，手动开始下一轮。" : "回到眼前这一件事。"
                    let sound = rest ? (plan.settings.restSound ?? "Glass") : (plan.settings.focusSound ?? "Pop")
                    content.sound = try PhoneSounds.shared.notificationSound(sound)
                    let request = UNNotificationRequest(identifier: "focus-mode-\(token)-\(index)", content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false))
                    try await center.add(request)
                    if generation != token { center.removePendingNotificationRequests(withIdentifiers: [request.identifier]); return }
                }
            } catch { report("提醒安排失败：\(error.localizedDescription)") }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Foreground audio is played by the timer, avoiding duplicate sounds.
        completionHandler([])
    }
}
