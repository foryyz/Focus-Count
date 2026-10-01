import FocusCountCore
import SwiftUI
import AppKit

@MainActor final class StudyStore: ObservableObject {
    @Published var database = Database()
    @Published var error: String?
    @Published var blocked = false
    private var ticker: Timer?
    private var ticks = 0
    @Published private(set) var modeSettings = FocusRoutineSettings()
    private var routineTick: Double?
    private var soundsEnabled = false
    private var modeDefaults: (any PreferenceStorage)?
    private let soundLibrary: SoundLibrary
    private var playingSound: NSSound?
    var isRunning: Bool {
        if let routine = database.focusRoutine { return !routine.suspended && routine.phase != .ready }
        return database.draft.isRunning
    }
    var isResting: Bool { database.focusRoutine.map { $0.phase != .focus } ?? false }
    func previewModeSound(id: String = "Glass", volume: Double? = nil) { playModeSound(id, volume: volume ?? modeSettings.volume) }
    private func playModeSound(_ name: String, volume: Double) {
        playingSound?.stop()
        playingSound = SoundLibrary.shared.sound(name)
        if playingSound == nil {
            error = "所选提示音无法播放，已使用默认提示音。请在设置中检查音频文件。"
            playingSound = NSSound(named: NSSound.Name("Glass"))
        }
        playingSound?.volume = Float(volume)
        playingSound?.play()
    }
    @discardableResult func setMode(_ settings: FocusRoutineSettings) -> Bool {
        guard settings.isValid, !blocked, database.pendingEnd == nil else { return false }
        advanceRoutine()
        let running = isRunning
        guard commit({ state in
            if settings.mode != modeSettings.mode {
                state.draft.pause()
                state.focusRoutine = nil
                if state.draft.startedAt != nil {
                    if settings.mode == .microBreak {
                        var routine = FocusRoutine(settings: settings); routine.suspended = !running
                        state.focusRoutine = routine
                    }
                    if running { state.draft.toggle() }
                }
            }
        }) else { return false }
        if let modeDefaults { SharedPreferences.capture(modeDefaults) }
        modeSettings = settings
        if let data = try? JSONEncoder().encode(settings) { modeDefaults?.set(data, forKey: "focus-modes-v1") }
        if let modeDefaults { SharedPreferences.capture(modeDefaults) }
        routineTick = StudyClock.now
        return true
    }
    func advanceRoutine(now: Double = StudyClock.now) {
        guard var routine = database.focusRoutine else { routineTick = nil; return }
        guard let previous = routineTick else { routineTick = now; return }
        let elapsed = max(0, now - previous)
        let phase = routine.phase
        let focused = routine.advance(elapsed)
        database.draft.accumulated += focused
        database.draft.runningSince = !routine.suspended && routine.phase == .focus ? now : nil
        database.focusRoutine = routine
        routineTick = now
        if phase != routine.phase && soundsEnabled && elapsed < 2 {
            let sound = (routine.phase == .microRest || routine.phase == .longRest)
                ? (routine.settings.restSound ?? "Glass") : (routine.settings.focusSound ?? "Pop")
            playModeSound(sound, volume: routine.settings.volume)
        }
    }
    func skipModeRest() {
        guard database.focusRoutine != nil else { return }
        advanceRoutine()
        _ = commit { state in
            if state.focusRoutine?.phase == .longRest || state.focusRoutine?.phase == .ready {
                let suspended = state.focusRoutine?.suspended ?? false
                state.focusRoutine = FocusRoutine(settings: modeSettings)
                state.focusRoutine?.suspended = suspended
            } else { state.focusRoutine?.skipRest() }
            if state.focusRoutine?.suspended == false { state.draft.runningSince = StudyClock.now }
        }
        routineTick = StudyClock.now
    }

    private var observers: [NSObjectProtocol] = []
    private var file: URL { get throws { try self.directory.appendingPathComponent("sessions.json") } }

    private let customDirectory: URL?
    private var directory: URL { get throws { try customDirectory ?? Storage.directory } }
    var sessions: [StudySession] { database.sessions.filter { $0.deletedAt == nil } }
    var subjects: [String] { Array(Set(sessions.map(\.subject))).sorted() }

    init(directory: URL? = nil, observeSystem: Bool = true) {
        soundLibrary = directory.map { SoundLibrary(directory: $0.appendingPathComponent("sounds")) } ?? SoundLibrary.shared
        customDirectory = directory
        soundsEnabled = observeSystem
        modeDefaults = directory.map { FilePreferences(directory: $0) } ?? FilePreferences.shared
        if let modeDefaults { SharedPreferences.capture(modeDefaults) }
        if let data = modeDefaults?.data(forKey: "focus-modes-v1"), let settings = try? JSONDecoder().decode(FocusRoutineSettings.self, from: data), settings.isValid { modeSettings = settings }
        do {
            if let failure = (modeDefaults as? FilePreferences)?.error {
                throw NSError(domain: "FocusCount.Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: failure])
            }
            if try FileManager.default.fileExists(atPath: file.path) {
                let contents = try Data(contentsOf: file)
                database = try JSONDecoder().decode(Database.self, from: contents)
                guard [1, 2, 3, 4, 5].contains(database.version) else { throw CocoaError(.fileReadUnknown) }
                let validated = try RecordExchange.decode(contents)
                database.sessions = validated.sessions
                database.events = validated.events
                if database.version < 5 {
                    let backup = try self.directory.appendingPathComponent("sessions.v\(database.version).backup.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try contents.write(to: backup, options: .atomic) }
                    database.version = 5
                    for index in database.sessions.indices {
                        database.sessions[index].updatedAt = database.sessions[index].updatedAt ?? database.sessions[index].endedAt
                    }
                }
            }
        } catch {
            blocked = true
            self.error = "无法读取数据，已停止写入以保护原文件。请检查数据目录：\(error.localizedDescription)"
        }
        if database.focusRoutine != nil {
            database.focusRoutine?.suspended = true
            routineTick = StudyClock.now
        }
        if !blocked {
            if database.draft.startedAt != nil && database.timerID == nil { database.timerID = UUID(); persist() }
            do { try writeCSV() } catch { self.error = "CSV 更新失败：\(error.localizedDescription)" }
        }
        guard observeSystem else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let previousPhase = self.database.focusRoutine?.phase
                self.advanceRoutine()
                if previousPhase != self.database.focusRoutine?.phase { _ = self.persist() }
                self.objectWillChange.send()
                self.ticks += 1
                if self.ticks % 20 == 0 && self.isRunning { self.persist() }
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForSleep() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAfterWake() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.persist() }
        })
    }
    @discardableResult func persist() -> Bool {
        guard !blocked else { return false }
        advanceRoutine()
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            var snapshot = database
            snapshot.draft = database.draft.checkpoint()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: file, options: .atomic)
            return true
        } catch { self.error = "保存失败：\(error.localizedDescription)"; return false }
    }
    func writeCSV() throws {
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try Data(Storage.csv(database.sessions).utf8).write(to: self.directory.appendingPathComponent("sessions.csv"), options: .atomic)
    }
    @discardableResult func markEvent(kind: String = "SEX", at date: Date = Date()) -> Bool {
        commit {
            if $0.events == nil { $0.events = [] }
            $0.events?.append(TimeEvent(kind: kind, occurredAt: date))
        }
    }
    @discardableResult func updateEvent(_ id: UUID, kind: String, at date: Date) -> Bool {
        let name = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, date <= Date(), database.events?.contains(where: { $0.id == id && $0.deletedAt == nil }) == true else { return false }
        return commit {
            guard let index = $0.events?.firstIndex(where: { $0.id == id }) else { return }
            let modified = max(Date(), $0.events![index].modified.addingTimeInterval(0.001))
            $0.events![index].kind = name
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
    func prepareForSleep() {
        if database.focusRoutine != nil { pause() }
        _ = persist()
    }
    func refreshAfterWake() {
        objectWillChange.send()
        _ = persist()
    }
    @discardableResult func cancelTimer() -> Bool {
        commit {
            $0.focusRoutine = nil
            $0.draft = TimerState()
            $0.activity = nil
            $0.timerID = nil
            $0.pendingEnd = nil
        }
    }
    func setActivity(_ activity: String) {
        guard !blocked, database.activity != activity else { return }
        database.activity = activity
        persist()
    }
    func toggle() {
        guard !blocked, database.pendingEnd == nil else { return }
        advanceRoutine()
        let beginsRound = database.draft.startedAt == nil || database.focusRoutine?.phase == .ready
        if database.draft.startedAt == nil {
            database.timerID = UUID()
            database.draft.toggle()
            if modeSettings.mode == .microBreak { database.focusRoutine = FocusRoutine(settings: modeSettings); routineTick = StudyClock.now }
        } else if var routine = database.focusRoutine {
            if routine.phase == .ready { routine = FocusRoutine(settings: modeSettings) }
            else { routine.suspended.toggle() }
            database.focusRoutine = routine
            database.draft.runningSince = !routine.suspended && routine.phase == .focus ? StudyClock.now : nil
            routineTick = StudyClock.now
        } else { database.draft.toggle() }
        if beginsRound, soundsEnabled, let routine = database.focusRoutine {
            playModeSound(routine.settings.focusSound ?? "Pop", volume: routine.settings.volume)
        }
        persist()
    }
    func pause() {
        advanceRoutine()
        database.focusRoutine?.suspended = true
        database.draft.pause(); persist()
    }
    func finish() {
        guard !blocked, database.draft.startedAt != nil else { return }
        pause()
        database.pendingEnd = Date()
        persist()
    }
    func resumeEditingTimer() { database.pendingEnd = nil; persist() }
    func save(subject: String, focus: String) -> Bool {
        guard !blocked, let start = database.draft.startedAt, let end = database.pendingEnd else { return false }
        if let id = database.timerID, (database.purgedIDs ?? []).contains(id) { error = "此次专注已彻底删除，请取消计时。"; return false }
        let session = StudySession(id: database.timerID ?? UUID(), startedAt: start, endedAt: end, activeSeconds: database.draft.seconds(), subject: subject.trimmingCharacters(in: .whitespacesAndNewlines), focus: focus, updatedAt: Date())
        return commit { database in
            database.sessions = RecordExchange.merge(local: database.sessions, incoming: [session], purgedIDs: database.purgedIDs ?? [])
            database.timerID = nil
            database.focusRoutine = nil
            database.draft = TimerState()
            database.activity = nil
            database.pendingEnd = nil
        }
    }
    private func commit(_ change: (inout Database) -> Void) -> Bool {
        guard !blocked else { return false }
        let old = database
        change(&database)
        error = nil
        guard persist() else { database = old; return false }
        do { try writeCSV() } catch { self.error = "记录已保存，但 CSV 更新失败：\(error.localizedDescription)" }
        return true
    }
    func upsert(_ session: StudySession) -> Bool {
        guard !(database.purgedIDs ?? []).contains(session.id) else { error = "此记录已彻底删除。"; return false }
        var edited = session
        edited.subject = edited.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = edited.validationError { error = problem; return false }
        edited.updatedAt = Date()
        return commit { database in
            if let index = database.sessions.firstIndex(where: { $0.id == edited.id }) {
                database.sessions[index] = RecordExchange.replacing(database.sessions[index], with: edited)
            } else { database.sessions.append(edited) }
        }
    }
    @discardableResult func setDeleted(_ id: UUID, deleted: Bool) -> Bool {
        guard let index = database.sessions.firstIndex(where: { $0.id == id }) else { return false }
        return commit { database in
            var changed = database.sessions[index]
            changed.deletedAt = deleted ? Date() : nil
            database.sessions[index] = RecordExchange.replacing(database.sessions[index], with: changed)
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
    func importRecords(_ incoming: Database, syncTimer: Bool = false, syncSounds: Bool = true, syncParameters: Bool = true) -> Bool {
        guard !blocked else { return false }
        do {
            let validated = try RecordExchange.decode(RecordExchange.encode(incoming))
            if syncTimer && validated.timerTransfer == nil { throw RecordExchange.ExchangeError.invalid("此文件不含可同步的计时状态，请在新版应用重新导出。") }
            if syncTimer, let id = validated.timerTransfer?.timerID,
               database.sessions.contains(where: { $0.id == id }) || validated.sessions.contains(where: { $0.id == id }) ||
                (database.purgedIDs ?? []).union(validated.purgedIDs ?? []).contains(id) {
                throw RecordExchange.ExchangeError.invalid("文件中的计时已保存或彻底删除，请关闭同步计时，只合并记录。")
            }
            let backupFolder = try directory.appendingPathComponent("backups/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
            try export().write(to: backupFolder.appendingPathComponent("before-import.json"), options: .atomic)
            try RecordExchange.encode(incoming).write(to: backupFolder.appendingPathComponent("incoming.json"), options: .atomic)
            var importedMode = modeSettings
            if let defaults = modeDefaults { importedMode = SharedPreferences.mergedMode(validated.sharedSettings, defaults: defaults, local: modeSettings, syncParameters: syncParameters) }
            if syncSounds, let audio = validated.soundPreferences {
                let available = Set(soundLibrary.sounds.map(\.id) + (validated.sounds ?? []).map(\.id))
                guard [audio.restSound, audio.focusSound].compactMap({ $0 }).allSatisfy({ available.contains($0) }) else {
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
            if syncSounds, let sounds = validated.sounds, !sounds.isEmpty { soundTransaction = try soundLibrary.stageSounds(sounds) }
            let success = commit {
                $0.goal = GoalSnapshot.merge($0.goal, validated.goal)
                $0.purgedIDs = ($0.purgedIDs ?? []).union(validated.purgedIDs ?? [])
                $0.sessions = RecordExchange.merge(local: $0.sessions, incoming: validated.sessions, purgedIDs: $0.purgedIDs ?? [])
                $0.events = RecordExchange.mergeEvents(local: $0.events ?? [], incoming: validated.events ?? [], purgedIDs: $0.purgedIDs ?? [])
                if syncTimer, let timer = validated.timerTransfer {
                    $0.focusRoutine = validated.focusRoutine
                    if var routine = $0.focusRoutine {
                        routine.settings.restSound = importedMode.restSound
                        routine.settings.focusSound = importedMode.focusSound
                        routine.settings.volume = importedMode.volume
                        let focus = routine.advance(max(0, Date().timeIntervalSince(timer.capturedAt)))
                        $0.focusRoutine = routine
                        $0.draft = TimerState(startedAt: timer.startedAt, accumulated: timer.accumulated + focus)
                        if !routine.suspended && routine.phase == .focus { $0.draft.toggle() }
                    }
                    $0.timerID = timer.timerID ?? (timer.startedAt == nil ? nil : UUID())
                    if $0.focusRoutine == nil { $0.draft = timer.timerState() }
                    $0.pendingEnd = timer.pendingEnd
                    $0.activity = timer.activity
                }
            }
            if success {
                if let settings = validated.sharedSettings, let defaults = modeDefaults {
                    SharedPreferences.apply(settings, defaults: defaults, syncParameters: syncParameters)
                }
                modeSettings = importedMode
                modeDefaults?.set(try JSONEncoder().encode(importedMode), forKey: "focus-modes-v1")
                routineTick = StudyClock.now
            }
            if success { soundTransaction?.finish(); importFinished = true }
            return success
        } catch { self.error = "导入未完成：\(error.localizedDescription)"; return false }
    }
    func export() throws -> Data {
        guard !blocked else { throw RecordExchange.ExchangeError.invalid("数据读取失败，无法导出。") }
        advanceRoutine()
        var snapshot = database
        snapshot.sharedSettings = modeDefaults.map { SharedPreferences.capture($0) }
        snapshot.sounds = try soundLibrary.exportSounds()
        snapshot.soundPreferences = SoundPreferences(modeSettings)
        snapshot.source = ExchangeSource(device: Host.current().localizedName ?? "Mac", platform: "macOS")
        let capturedAt = Date()
        snapshot.draft = database.draft.checkpoint()
        snapshot.timerTransfer = TimerTransfer(capturedAt: capturedAt, startedAt: snapshot.draft.startedAt,
            accumulated: snapshot.draft.accumulated, isRunning: database.draft.isRunning,
            pendingEnd: database.pendingEnd, activity: database.activity, timerID: database.timerID)
        snapshot.focusRoutine?.settings.restSound = nil
        snapshot.focusRoutine?.settings.focusSound = nil
        snapshot.focusRoutine?.settings.volume = FocusRoutineSettings().volume
        return try RecordExchange.encode(snapshot)
    }
    @discardableResult func deleteAllHistory() -> Bool {
        guard !blocked else { return false }
        do {
            let archives = try importArchives()
            // Persist deletion markers first; a failed database write must not remove backups.
            guard commit({ $0.sessions = $0.sessions.map { RecordExchange.deletingAllVersions(from: $0) } }) else { return false }
            for archive in archives { try archive.delete(directory: directory, phone: false) }
            error = nil
            return true
        } catch {
            self.error = "清理未全部完成，剩余备份仍在列表中，可重试：\(error.localizedDescription)"
            return false
        }
    }
    @discardableResult func deleteArchive(_ archive: ImportArchive) -> Bool {
        guard !blocked else { return false }
        do { try archive.delete(directory: directory, phone: false); error = nil; return true }
        catch { self.error = "备份删除失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func deleteVersion(_ snapshot: SessionSnapshot) -> Bool {
        guard database.sessions.contains(where: { $0.id == snapshot.sessionID && ($0.history ?? []).contains(where: { $0.id == snapshot.id }) }) else { return false }
        return commit {
            guard let index = $0.sessions.firstIndex(where: { $0.id == snapshot.sessionID }) else { return }
            $0.sessions[index] = RecordExchange.deletingVersion(snapshot, from: $0.sessions[index])
        }
    }
    func importArchives() throws -> [ImportArchive] { try ImportArchive.list(directory: directory, phone: false) }
    func importPreview(_ incoming: Database, syncParameters: Bool, syncSounds: Bool = true) -> [String] {
        var local = database
        local.sharedSettings = modeDefaults.map { SharedPreferences.capture($0) }
        // Compare numbers against the actual defaults, even before they have been saved.
        var changes = ExchangePreview.changes(local: local, incoming: incoming, syncParameters: false)
        let nextMode = modeDefaults.map { SharedPreferences.mergedMode(incoming.sharedSettings, defaults: $0, local: modeSettings, syncParameters: syncParameters) } ?? modeSettings
        if ModeParameters(nextMode) != ModeParameters(modeSettings) { changes.append("更新模式数值参数") }
        if syncSounds {
            let changedSounds = (incoming.sounds ?? []).filter { sound in
                guard let old = soundLibrary.custom.first(where: { $0.id == sound.id }) else { return true }
                let oldDate = old.modified ?? .distantPast
                return sound.modified > oldDate || (sound.modified == oldDate && sound.name > old.name)
            }.count
            if changedSounds > 0 { changes.append("合并 \(changedSounds) 个新增或更新的自定义提示音（含文件）") }
            if let audio = incoming.soundPreferences, audio != SoundPreferences(modeSettings) { changes.append("更新提示音选择与音量") }
        }
        return changes
    }
    func restoreVersion(_ snapshot: SessionSnapshot) -> Bool {
        guard let current = database.sessions.first(where: { $0.id == snapshot.sessionID }),
              (current.history ?? []).contains(where: { $0.id == snapshot.id }),
              !(current.purgedHistoryIDs ?? []).contains(snapshot.id) else { return false }
        // Restore as a new edit, retaining both the current and all archived versions.
        return commit { database in
            if let index = database.sessions.firstIndex(where: { $0.id == current.id }) {
                database.sessions[index] = RecordExchange.replacing(current, with: snapshot.session)
            }
        }
    }
}

enum FocusCommand: Equatable {
    case mark(String), unknown
    init(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("!") else { self = .unknown; return }
        let label = String(value.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = label.isEmpty ? .unknown : .mark(label)
    }
}
