import SwiftUI
import FocusCountCore

struct PhoneState: Codable {
    var modeSettings: FocusRoutineSettings?
    var routine: PhoneRoutine?
    var goal: GoalSnapshot?
    var version = 5
    var events: [TimeEvent]?
    var purgedIDs: Set<UUID>?
    var sessions: [StudySession] = []
    var clock = MobileClock()
    var activity: String?
    var timerID: UUID?
}

@MainActor final class PhoneStore: ObservableObject {
    @Published private(set) var state = PhoneState()
    @Published var error: String?
    @Published var notificationIssue: String?
    @Published private(set) var blocked = false
    @Published private(set) var showingHome = false
    /// Returning home pauses the existing timer; no new round is created.
    func returnHome() {
        guard !blocked, state.clock.startedAt != nil, state.clock.pendingEnd == nil else { return }
        if isRunning { toggle() }
        guard !isRunning else { return }
        showingHome = true
    }
    @discardableResult func resumeFocus() -> Bool {
        guard !blocked, state.clock.startedAt != nil, state.clock.pendingEnd == nil else { return false }
        if !isRunning { toggle() }
        guard isRunning else { return false }
        showingHome = false
        return true
    }
    private var ticker: Timer?
    private let live: Bool
    private let preferences: UserDefaults
    let soundLibrary: PhoneSounds
    private var ticks = 0
    var modeSettings: FocusRoutineSettings { state.modeSettings ?? FocusRoutineSettings() }
    var isRunning: Bool { state.routine.map { !$0.suspended && $0.phase != .ready } ?? state.clock.isRunning }
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("app-state.json") }
    var sessions: [StudySession] { state.sessions.filter { $0.deletedAt == nil } }
    var subjects: [String] { Array(Set(sessions.map(\.subject))).sorted() }

    init(directory: URL? = nil) {
        live = directory == nil
        preferences = directory == nil ? .standard : UserDefaults(suiteName: "FocusCount-test-" + Data(directory!.path.utf8).base64EncodedString())!
        soundLibrary = directory.map { PhoneSounds(directory: $0.appendingPathComponent("sounds")) } ?? PhoneSounds.shared
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FocusCount", isDirectory: true)
        if directory == nil {
            // Make an offline export destination visible in the Files app.
            let exports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
            try? FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        }
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                var loaded = try JSONDecoder().decode(PhoneState.self, from: data)
                guard [1, 2, 3, 4, 5].contains(loaded.version), loaded.clock.isValid, loaded.routine?.isValid ?? true, loaded.modeSettings?.isValid ?? true else { throw CocoaError(.fileReadCorruptFile) }
                // Validate the records with the same rules as interchange files.
                let validated = try RecordExchange.decode(RecordExchange.encode(Database(events: loaded.events, purgedIDs: loaded.purgedIDs, sessions: loaded.sessions, goal: loaded.goal)))
                loaded.sessions = validated.sessions
                loaded.events = validated.events
                if loaded.version < 5 {
                    let backup = self.directory.appendingPathComponent("app-state.v\(loaded.version).backup.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) }
                    loaded.version = 5
                }
                state = loaded
                if state.clock.startedAt != nil && state.timerID == nil { _ = commit { $0.timerID = UUID() } }
            }
        } catch { blocked = true; self.error = "无法读取本地数据，已停止写入保护原文件。\n\(error.localizedDescription)" }
        if preferences.data(forKey: "focus-modes-v1") == nil, let settings = state.modeSettings, let data = try? JSONEncoder().encode(settings) { preferences.set(data, forKey: "focus-modes-v1") }
        SharedPreferences.capture(preferences)
        if live {
            tick()
            refreshNotifications()
            ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }
    private func settled(_ original: PhoneState, at date: Date) -> PhoneState {
        var next = original
        if var routine = next.routine {
            next.clock.accumulated += routine.advance(at: date)
            next.clock.runningSince = !routine.suspended && routine.phase == .focus ? date : nil
            next.routine = routine
        }
        return next
    }
    func tick(at date: Date = Date()) {
        guard !blocked, let old = state.routine else { return }
        state = settled(state, at: date)
        if live, let plan = state.routine, old.phase != plan.phase,
           date.timeIntervalSince(old.anchor) < 2, UIApplication.shared.applicationState == .active {
            PhoneSounds.shared.play((plan.phase == .microRest || plan.phase == .longRest) ? plan.settings.activeRestSound : plan.settings.activeFocusSound, volume: plan.settings.volume)
        }
        if old.phase != state.routine?.phase, state.routine?.settings.mode == .course { refreshNotifications() }
        ticks += 1
        if ticks % 40 == 0 || old.phase != state.routine?.phase { _ = commit { _ in } }
    }
    private func refreshNotifications() {
        guard live else { return }
        notificationIssue = nil
        PhoneNotifications.shared.replace(state.routine) { [weak self] issue in self?.notificationIssue = issue }
    }
    @discardableResult func setMode(_ settings: FocusRoutineSettings) -> Bool {
        guard settings.isValid, state.clock.pendingEnd == nil else { return false }
        let previousMode = modeSettings.mode
        let success = commit { next in
            if previousMode != settings.mode, next.clock.startedAt != nil {
                let running = next.routine.map { !$0.suspended && $0.phase != .ready } ?? next.clock.isRunning
                next.clock.pause()
                next.routine = nil
                if settings.mode != .standard {
                    var plan = PhoneRoutine(settings: settings); plan.suspended = !running
                    next.routine = plan
                }
                if running { next.clock.toggle() }
            }
            next.modeSettings = settings
            next.routine?.settings.standardVolume = settings.standardVolume
            next.routine?.settings.microBreakVolume = settings.microBreakVolume
            next.routine?.settings.courseVolume = settings.courseVolume
        }
        if success {
            SharedPreferences.capture(preferences)
            if let data = try? JSONEncoder().encode(settings) { preferences.set(data, forKey: "focus-modes-v1") }
            SharedPreferences.capture(preferences)
            refreshNotifications()
        }
        return success
    }
    @discardableResult func deleteCustomSound(_ id: String) -> Bool {
        guard !blocked else { return false }
        var transaction: SoundFileTransaction?
        do {
            transaction = try soundLibrary.stageDeletion(id)
            let settings = modeSettings.removingSound(id)
            guard commit({ next in
                next.modeSettings = settings
                if var plan = next.routine { plan.settings = plan.settings.removingSound(id); next.routine = plan }
            }) else { throw NSError(domain: "FocusCount.Sound", code: 1, userInfo: [NSLocalizedDescriptionKey: error ?? "无法保存模式设置"]) }
            preferences.set(try JSONEncoder().encode(settings), forKey: "focus-modes-v1")
            SharedPreferences.capture(preferences)
            transaction?.finish()
            refreshNotifications()
            soundLibrary.error = nil
            soundLibrary.notice = "已删除提示音；使用该声音的提醒已恢复默认。"
            return true
        } catch {
            var message = "删除失败：\(error.localizedDescription)"
            do { try transaction?.rollback() } catch { message += "；回滚失败：\(error.localizedDescription)" }
            self.error = message; soundLibrary.error = message; soundLibrary.notice = nil
            return false
        }
    }
    func skipRest() {
        let success = commit { next in
            guard var plan = next.routine else { return }
            let suspended = plan.suspended
            if plan.phase == .longRest || plan.phase == .ready { plan = PhoneRoutine(settings: plan.settings.mode == modeSettings.mode ? modeSettings : plan.settings); plan.suspended = suspended }
            else { plan.skipRest(at: Date()) }
            next.routine = plan
            next.clock.runningSince = !plan.suspended && plan.phase == .focus ? Date() : nil
        }
        if success {
            refreshNotifications()
            if live, let plan = state.routine, plan.settings.mode == .course, !plan.suspended, plan.phase == .focus {
                PhoneSounds.shared.play(plan.settings.activeFocusSound, volume: plan.settings.volume)
            }
        }
    }
    @discardableResult private func commit(_ change: (inout PhoneState) -> Void) -> Bool {
        guard !blocked else { return false }
        var next = settled(state, at: Date()); change(&next)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: file, options: .atomic)
            state = next; error = nil
            if next.clock.startedAt == nil { showingHome = false }
            if live && next.routine == nil { refreshNotifications() }
            return true
        } catch { self.error = "保存失败，修改未生效：\(error.localizedDescription)"; return false }
    }
    @discardableResult func cancelTimer() -> Bool {
        let success = commit { $0.clock = MobileClock(); $0.activity = nil; $0.timerID = nil; $0.routine = nil }
        if success { refreshNotifications() }; return success
    }
    @discardableResult func start(activity: String) -> Bool {
        guard state.clock.startedAt == nil else { return false }
        let success = commit {
            $0.timerID = UUID()
            $0.activity = activity.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.clock.toggle()
            if modeSettings.mode != .standard { $0.routine = PhoneRoutine(settings: modeSettings) }
        }
        if success { refreshNotifications(); playStart() }; return success
    }
    @discardableResult func markCommand(_ command: String, at date: Date = Date()) -> Bool {
        let input = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.hasPrefix("!") else { error = "输入 ! 加标记文字，例如 !sad。"; return false }
        return markEvent(kind: String(input.dropFirst()), at: date)
    }
    @discardableResult func markEvent(kind: String = "sex", at date: Date = Date()) -> Bool {
        let label = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !label.isEmpty else { error = "请在 ! 后填写标记文字。"; return false }
        return commit {
            if $0.events == nil { $0.events = [] }
            $0.events?.append(TimeEvent(kind: label, occurredAt: date))
        }
    }
    @discardableResult func updateEvent(_ id: UUID, kind: String, at date: Date) -> Bool {
        let label = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !label.isEmpty, date <= Date(), state.events?.contains(where: { $0.id == id && $0.deletedAt == nil }) == true else { return false }
        return commit {
            guard let index = $0.events?.firstIndex(where: { $0.id == id }) else { return }
            let modified = max(Date(), $0.events![index].modified.addingTimeInterval(0.001))
            $0.events![index].kind = label
            $0.events![index].occurredAt = date
            $0.events![index].updatedAt = modified
        }
    }
    @discardableResult func setEventDeleted(_ id: UUID, deleted: Bool) -> Bool {
        commit {
            guard let index = $0.events?.firstIndex(where: { $0.id == id }) else { return }
            let now = max(Date(), $0.events![index].modified.addingTimeInterval(0.001))
            $0.events![index].deletedAt = deleted ? now : nil
            $0.events![index].updatedAt = now
        }
    }
    @discardableResult func purgeEvents(_ ids: Set<UUID>) -> Bool {
        commit {
            let removed = Set(($0.events ?? []).filter { ids.contains($0.id) && $0.deletedAt != nil }.map(\.id))
            $0.purgedIDs = ($0.purgedIDs ?? []).union(removed)
            $0.events?.removeAll { removed.contains($0.id) }
        }
    }
    private func playStart() {
        guard live else { return }
        if let plan = state.routine { PhoneSounds.shared.play(plan.settings.activeFocusSound, volume: plan.settings.volume) }
        else { PhoneSounds.shared.play(modeSettings.startSound ?? "Pop", volume: modeSettings.volume(for: .standard)) }
    }
    func toggle() {
        if state.clock.startedAt == nil { _ = start(activity: state.activity ?? ""); return }
        guard state.clock.pendingEnd == nil else { return }
        let wasRunning = isRunning
        let newRound = state.routine?.phase == .ready
        let success = commit { next in
            if var plan = next.routine {
                if plan.phase == .ready { plan = PhoneRoutine(settings: plan.settings.mode == modeSettings.mode ? modeSettings : plan.settings) }
                else { plan.suspended.toggle(); plan.anchor = Date() }
                next.routine = plan
                next.clock.runningSince = !plan.suspended && plan.phase == .focus ? Date() : nil
            } else { next.clock.toggle() }
        }
        if success {
            refreshNotifications()
            if newRound || (state.routine == nil && !wasRunning && isRunning) { playStart() }
            else if live, state.routine == nil, wasRunning && !isRunning {
                PhoneSounds.shared.play(modeSettings.pauseSound ?? "Glass", volume: modeSettings.volume(for: .standard))
            }
        }
    }
    func finish() {
        if commit({ $0.clock.finish(); $0.routine?.suspended = true }) { refreshNotifications() }
    }
    func returnToTimer() { commit { $0.clock.pendingEnd = nil } }
    func checkpoint() { commit { _ in } }
    func becameActive() { tick(); refreshNotifications() }
    func save(_ session: StudySession, completesTimer: Bool = false) -> Bool {
        guard !(state.purgedIDs ?? []).contains(completesTimer ? (state.timerID ?? session.id) : session.id) else { error = "此记录已彻底删除。"; return false }
        var edited = session
        if completesTimer, let id = state.timerID { edited.id = id }
        edited.subject = edited.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = edited.validationError { error = issue; return false }
        edited.updatedAt = Date()
        return commit {
            if let index = $0.sessions.firstIndex(where: { $0.id == edited.id }) { $0.sessions[index] = RecordExchange.replacing($0.sessions[index], with: edited) }
            else { $0.sessions.append(edited) }
            if completesTimer { $0.clock = MobileClock(); $0.activity = nil; $0.timerID = nil; $0.routine = nil }
        }
    }
    func delete(_ session: StudySession, restore: Bool = false) {
        commit {
            guard let index = $0.sessions.firstIndex(where: { $0.id == session.id }) else { return }
            var changed = $0.sessions[index]
            changed.deletedAt = restore ? nil : Date()
            $0.sessions[index] = RecordExchange.replacing($0.sessions[index], with: changed)
        }
    }
    @discardableResult func permanentlyDelete(_ ids: Set<UUID>) -> Bool {
        return commit {
            let removed = Set($0.sessions.filter { ids.contains($0.id) && $0.deletedAt != nil }.map(\.id))
            $0.purgedIDs = ($0.purgedIDs ?? []).union(removed)
            $0.sessions.removeAll { removed.contains($0.id) }
        }
    }
    @discardableResult func updateGoal(_ goal: GoalSnapshot) -> Bool {
        guard goal.isValid else { return false }
        return commit { $0.goal = goal }
    }
    func importRecords(_ database: Database, syncTimer: Bool = false, syncSounds: Bool = true, syncParameters: Bool = true) -> Bool {
        guard !blocked else { return false }
        do {
            let incoming = try RecordExchange.decode(RecordExchange.encode(database))
            if syncTimer && incoming.timerTransfer == nil { throw RecordExchange.ExchangeError.invalid("此文件不含可同步的计时状态，请在新版应用重新导出。") }
            if syncTimer, let id = incoming.timerTransfer?.timerID,
               state.sessions.contains(where: { $0.id == id }) || incoming.sessions.contains(where: { $0.id == id }) ||
                (state.purgedIDs ?? []).union(incoming.purgedIDs ?? []).contains(id) {
                throw RecordExchange.ExchangeError.invalid("文件中的计时已保存或彻底删除，请关闭同步计时，只合并记录。")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let identifier = UUID().uuidString
            try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("before-import-\(identifier).json"), options: .atomic)
            try export(forBackup: true).write(to: directory.appendingPathComponent("before-import-complete-\(identifier).json"), options: .atomic)
            try RecordExchange.encode(database).write(to: directory.appendingPathComponent("incoming-\(identifier).json"), options: .atomic)
            var importedMode = modeSettings
            importedMode = SharedPreferences.mergedMode(incoming.sharedSettings, defaults: preferences, local: modeSettings, syncParameters: syncParameters)
            if syncSounds, let audio = incoming.soundPreferences {
                let available = Set(soundLibrary.sounds.map(\.id) + (incoming.sounds ?? []).map(\.id))
                guard [audio.restSound, audio.focusSound, audio.classStartSound, audio.classEndSound, audio.startSound, audio.pauseSound].compactMap({ $0 }).allSatisfy({ available.contains($0) }) else {
                    throw RecordExchange.ExchangeError.invalid("提示音设置引用了缺失的音频，请关闭提示音同步或重新导出。")
                }
                importedMode = audio.applying(to: importedMode)
            }
            var soundTransaction: SoundFileTransaction?
            var importFinished = false
            defer {
                if !importFinished, let soundTransaction {
                    do { try soundTransaction.rollback() } catch { self.error = "提示音回滚失败，请保留备份：\(error.localizedDescription)" }
                }
            }
            if syncSounds, let sounds = incoming.sounds, !sounds.isEmpty { soundTransaction = try soundLibrary.stageSounds(sounds) }
            let success = commit {
                $0.modeSettings = importedMode
                $0.goal = GoalSnapshot.merge($0.goal, incoming.goal)
                $0.purgedIDs = ($0.purgedIDs ?? []).union(incoming.purgedIDs ?? [])
                $0.sessions = RecordExchange.merge(local: $0.sessions, incoming: incoming.sessions, purgedIDs: $0.purgedIDs ?? [])
                $0.events = RecordExchange.mergeEvents(local: $0.events ?? [], incoming: incoming.events ?? [], purgedIDs: $0.purgedIDs ?? [])
                if syncTimer, let timer = incoming.timerTransfer {
                    $0.routine = nil
                    if var routine = incoming.focusRoutine {
                        routine.settings = SoundPreferences(importedMode).applying(to: routine.settings)
                        let focus = routine.advance(max(0, Date().timeIntervalSince(timer.capturedAt)))
                        $0.routine = PhoneRoutine(routine: routine)
                        $0.clock = MobileClock(); $0.clock.startedAt = timer.startedAt
                        $0.clock.accumulated = timer.accumulated + focus
                        $0.clock.runningSince = !routine.suspended && routine.phase == .focus ? Date() : nil
                        $0.clock.pendingEnd = timer.pendingEnd
                    }
                    $0.timerID = timer.timerID ?? (timer.startedAt == nil ? nil : UUID())
                    if $0.routine == nil { $0.clock = timer.mobileClock() }
                    $0.activity = timer.activity
                }
            }
            if success {
                if let settings = incoming.sharedSettings {
                    SharedPreferences.apply(settings, defaults: preferences, syncParameters: syncParameters)
                }
                preferences.set(try JSONEncoder().encode(importedMode), forKey: "focus-modes-v1")
                refreshNotifications()
            }
            if success { soundTransaction?.finish(); importFinished = true }
            return success
        } catch { self.error = "导入未完成：\(error.localizedDescription)"; return false }
    }
    @discardableResult func deleteAllHistory() -> Bool {
        guard !blocked else { return false }
        do {
            let archives = try importArchives()
            // Persist deletion markers first; a failed database write must not remove backups.
            guard commit({ $0.sessions = $0.sessions.map { RecordExchange.deletingAllVersions(from: $0) } }) else { return false }
            for archive in archives { try archive.delete(directory: directory, phone: true) }
            error = nil
            return true
        } catch {
            self.error = "清理未全部完成，剩余备份仍在列表中，可重试：\(error.localizedDescription)"
            return false
        }
    }
    @discardableResult func deleteArchive(_ archive: ImportArchive) -> Bool {
        guard !blocked else { return false }
        do { try archive.delete(directory: directory, phone: true); error = nil; return true }
        catch { self.error = "备份删除失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func deleteVersion(_ snapshot: SessionSnapshot) -> Bool {
        guard state.sessions.contains(where: { $0.id == snapshot.sessionID && ($0.history ?? []).contains(where: { $0.id == snapshot.id }) }) else { return false }
        return commit {
            guard let index = $0.sessions.firstIndex(where: { $0.id == snapshot.sessionID }) else { return }
            $0.sessions[index] = RecordExchange.deletingVersion(snapshot, from: $0.sessions[index])
        }
    }
    func importArchives() throws -> [ImportArchive] { try ImportArchive.list(directory: directory, phone: true) }
    func importPreview(_ incoming: Database, syncParameters: Bool, syncSounds: Bool = true) -> [String] {
        var local = Database(events: state.events, purgedIDs: state.purgedIDs, sessions: state.sessions, goal: state.goal)
        local.sharedSettings = SharedPreferences.capture(preferences, persist: false)
        // Compare numbers against the actual defaults, even before they have been saved.
        var changes = ExchangePreview.changes(local: local, incoming: incoming, syncParameters: false)
        let nextMode = SharedPreferences.mergedMode(incoming.sharedSettings, defaults: preferences, local: modeSettings, syncParameters: syncParameters)
        if ModeParameters(nextMode) != ModeParameters(modeSettings) { changes.append("更新模式数值参数") }
        if syncSounds {
            let changedSounds = (incoming.sounds ?? []).filter { sound in
                guard let old = soundLibrary.custom.first(where: { $0.id == sound.id }) else { return true }
                let oldDate = old.modified ?? .distantPast
                return sound.modified > oldDate || (sound.modified == oldDate && sound.name > old.name)
            }.count
            if changedSounds > 0 { changes.append("合并 \(changedSounds) 个新增或更新的自定义提示音（含文件）") }
            if let audio = incoming.soundPreferences, SoundPreferences(audio.applying(to: modeSettings)) != SoundPreferences(modeSettings) { changes.append("更新提示音选择与音量") }
        }
        return changes
    }
    func restoreVersion(_ snapshot: SessionSnapshot) {
        guard let current = state.sessions.first(where: { $0.id == snapshot.sessionID }),
              (current.history ?? []).contains(where: { $0.id == snapshot.id }),
              !(current.purgedHistoryIDs ?? []).contains(snapshot.id) else { return }
        commit {
            guard let index = $0.sessions.firstIndex(where: { $0.id == snapshot.sessionID }) else { return }
            $0.sessions[index] = RecordExchange.replacing($0.sessions[index], with: snapshot.session)
        }
    }
    func export(forBackup: Bool = false) throws -> Data {
        guard !blocked else { throw RecordExchange.ExchangeError.invalid("本地数据读取失败，无法导出。") }
        tick()
        let capturedAt = Date()
        let draft = TimerState(startedAt: state.clock.startedAt, accumulated: state.clock.seconds(at: capturedAt))
        let transfer = TimerTransfer(capturedAt: capturedAt, startedAt: draft.startedAt, accumulated: draft.accumulated,
            isRunning: state.clock.isRunning, pendingEnd: state.clock.pendingEnd, activity: state.activity, timerID: state.timerID)
        var snapshot = Database(events: state.events, purgedIDs: state.purgedIDs, sessions: state.sessions, draft: draft, pendingEnd: state.clock.pendingEnd, timerTransfer: transfer, activity: state.activity, goal: state.goal)
        snapshot.sharedSettings = SharedPreferences.capture(preferences)
        let options = forBackup ? SyncExportOptions(sounds: true, parameters: true, goal: true) : SyncPreferences.exportOptions(from: preferences)
        snapshot.sounds = options.sounds ? try soundLibrary.exportSounds() : nil
        snapshot.soundPreferences = options.sounds ? SoundPreferences(modeSettings) : nil
        snapshot.source = ExchangeSource(device: UIDevice.current.name, platform: "iPhone")
        snapshot.focusRoutine = state.routine?.portable
        snapshot.focusRoutine?.settings.restSound = nil
        snapshot.focusRoutine?.settings.focusSound = nil
        snapshot.focusRoutine?.settings.classStartSound = nil
        snapshot.focusRoutine?.settings.classEndSound = nil
        snapshot.focusRoutine?.settings.startSound = nil
        snapshot.focusRoutine?.settings.pauseSound = nil
        snapshot.focusRoutine?.settings.standardVolume = FocusRoutineSettings().standardVolume
        snapshot.focusRoutine?.settings.microBreakVolume = FocusRoutineSettings().microBreakVolume
        snapshot.focusRoutine?.settings.courseVolume = FocusRoutineSettings().courseVolume
        return try RecordExchange.encode(options.filtering(snapshot))
    }
}

func phoneDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "--:--:--" }
    let value = Int(seconds)
    return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
}

// Kept for callers using the previous phone-specific name.
enum PhoneImportFile {
    static func read(_ url: URL) throws -> Data { try ExchangeFileReader.read(url) }
}
