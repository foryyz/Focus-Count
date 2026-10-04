import FocusCountCore
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UserNotifications

struct PhoneSound: Codable, Identifiable {
    let id: String
    var name: String
    var file: String?
    var modified: Date?
}

@MainActor final class PhoneSounds: ObservableObject {
    static let shared = PhoneSounds()
    static let presets = [PhoneSound(id: "Glass", name: "清脆"), PhoneSound(id: "Pop", name: "轻点"), PhoneSound(id: "Hero", name: "明亮"), PhoneSound(id: "Ping", name: "叮咚"), PhoneSound(id: "Tink", name: "轻铃"), PhoneSound(id: "Submarine", name: "水滴")]
    @Published private(set) var custom: [PhoneSound] = []
    @Published var error: String?
    @Published var notice: String?
    private var readable = true
    private var player: AVAudioPlayer?
    let directory: URL
    var sounds: [PhoneSound] { Self.presets + custom }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FocusCount/sounds")
        let index = self.directory.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: index.path) {
            do { custom = try JSONDecoder().decode([PhoneSound].self, from: Data(contentsOf: index)) }
            catch { readable = false; self.error = "提示音库读取失败：\(error.localizedDescription)" }
        }
    }
    func url(_ id: String) -> URL? {
        if Self.presets.contains(where: { $0.id == id }) { return Bundle.main.url(forResource: id, withExtension: "wav", subdirectory: "Sounds") }
        guard let file = custom.first(where: { $0.id == id })?.file, file == URL(fileURLWithPath: file).lastPathComponent else { return nil }
        return directory.appendingPathComponent(file)
    }
    func notificationSound(_ id: String) throws -> UNNotificationSound {
        guard let source = url(id) else { return .default }
        let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(id + ".caf")
        let sourceDate = (try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let cacheDate = (try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if !FileManager.default.fileExists(atPath: destination.path) || sourceDate > cacheDate {
            let input = try AVAudioFile(forReading: source)
            let format = input.processingFormat
            // Notification audio must be shorter than 30 seconds. Use the first 29 seconds.
            let frames = AVAudioFrameCount(min(input.length, AVAudioFramePosition(format.sampleRate * 29)))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return .default }
            try input.read(into: buffer)
            let output = try AVAudioFile(forWriting: destination, settings: format.settings)
            try output.write(from: buffer)
        }
        return UNNotificationSound(named: UNNotificationSoundName(destination.lastPathComponent))
    }
    func play(_ id: String, volume: Double = 0.4) {
        do {
            player?.stop()
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            guard let file = url(id) else { throw CocoaError(.fileNoSuchFile) }
            player = try AVAudioPlayer(contentsOf: file)
            player?.volume = Float(volume); player?.play()
        } catch {
            self.error = "提示音无法播放：\(error.localizedDescription)"
            if id != "Glass" { play("Glass", volume: volume) }
        }
    }
    private func save(_ items: [PhoneSound]) throws {
        guard readable else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
        custom = items; error = nil
    }
    func add(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var failure: NSError?
        var outcome: Result<Void, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failure) { source in
            outcome = Result {
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 50 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                _ = try AVAudioPlayer(contentsOf: source)
                let id = UUID().uuidString
                let file = id + "." + source.pathExtension
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(file)
                try FileManager.default.copyItem(at: source, to: destination)
                do { try save(custom + [PhoneSound(id: id, name: String(source.deletingPathExtension().lastPathComponent.prefix(80)), file: file, modified: Date())]) }
                catch { try? FileManager.default.removeItem(at: destination); throw error }
            }
        }
        if let failure { throw failure }
        guard let outcome else { throw CocoaError(.fileReadUnknown) }
        try outcome.get()
        notice = "已导入“\(custom.last?.name ?? "")”，可在模式设置中选择。"
    }
    func exportSounds() throws -> [SharedSound] {
        let folder = directory
        return try custom.map { item in
            guard let file = item.file, file == URL(fileURLWithPath: file).lastPathComponent else { throw CocoaError(.fileReadCorruptFile) }
            let url = folder.appendingPathComponent(file)
            return SharedSound(id: item.id, name: item.name, fileExtension: url.pathExtension, data: try Data(contentsOf: url), modified: item.modified ?? .distantPast)
        }
    }
    func importSounds(_ incoming: [SharedSound]) throws {
        let transaction = try stageSounds(incoming)
        transaction.finish()
    }
    func stageSounds(_ incoming: [SharedSound]) throws -> SoundFileTransaction {
        guard readable else { throw CocoaError(.fileReadCorruptFile) }
        let folder = directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let previous = custom
        var next = custom
        var files: [String: Data] = [:]
        for sound in incoming {
            guard sound.isValid else { throw CocoaError(.fileReadCorruptFile) }
            if let old = next.first(where: { $0.id == sound.id }), (old.modified ?? .distantPast) > sound.modified || ((old.modified ?? .distantPast) == sound.modified && old.name > sound.name) { continue }
            let file = sound.id + "." + sound.fileExtension
            _ = try AVAudioPlayer(data: sound.data)
            files[file] = sound.data
            let entry = PhoneSound(id: sound.id, name: sound.name, file: file, modified: sound.modified)
            next.removeAll { $0.id == sound.id }; next.append(entry)
        }
        let transaction = try SoundFileTransaction(directory: folder, files: files, index: JSONEncoder().encode(next)) { [weak self] in self?.custom = previous }
        custom = next
        return transaction
    }
    @discardableResult func rename(_ id: String, name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { error = "名称请填写 1–80 个字符。"; notice = nil; return false }
        guard let index = custom.firstIndex(where: { $0.id == id }) else { error = "提示音不存在，请刷新列表。"; return false }
        var items = custom; items[index].name = name; items[index].modified = Date()
        do { try save(items); notice = "已保存“\(name)”"; return true }
        catch { self.error = "名称保存失败：\(error.localizedDescription)"; notice = nil; return false }
    }
    func stageDeletion(_ id: String) throws -> SoundFileTransaction {
        guard let item = custom.first(where: { $0.id == id }), let file = item.file else { throw CocoaError(.fileNoSuchFile) }
        let folder = directory
        player?.stop()
        let cache = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds").appendingPathComponent(id + ".caf")
        guard UUID(uuidString: id) != nil else { throw CocoaError(.fileReadCorruptFile) }
        if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
        let previous = custom, next = custom.filter { $0.id != id }
        let transaction = try SoundFileTransaction(directory: folder, files: [:], index: JSONEncoder().encode(next), removing: [file]) { [weak self] in self?.custom = previous }
        custom = next
        error = nil
        return transaction
    }

}

struct PhoneSoundSettings: View {
    @ObservedObject var store: PhoneStore
    @ObservedObject private var sounds: PhoneSounds
    init(store: PhoneStore) { self.store = store; self.sounds = store.soundLibrary }
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SyncPreferences.soundsKey) private var syncSounds = false
    @AppStorage(SyncPreferences.parametersKey) private var syncParameters = false
    @AppStorage(SyncPreferences.goalKey) private var syncGoal = true
    @State private var importing = false
    @State private var deleting: PhoneSound?
    @State private var renameID: String?
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                Section("主题") { ThemeSettingsContent() }
                Section("我的提示音") {
                    Button { importing = true } label: { Label("导入音频", systemImage: "plus.circle") }
                    if let notice = sounds.notice, sounds.error == nil { Label(notice, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green) }
                    if sounds.custom.isEmpty { Text("还没有自定义提示音").foregroundStyle(.secondary) }
                    ForEach(sounds.custom) { sound in
                        HStack {
                            Button(sound.name) { name = sound.name; renameID = sound.id }.foregroundStyle(.primary).buttonStyle(.borderless)
                            Spacer(); preview(sound)
                            Button(role: .destructive) { deleting = sound } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.buttonStyle(.borderless).disabled(store.blocked).accessibilityLabel("删除" + sound.name)
                        }
                    }
                }
                Section {
                    Toggle("同步自定义提示音与声音设置", isOn: $syncSounds)
                    Toggle("同步模式数值参数", isOn: $syncParameters)
                    Toggle("同步目标日期", isOn: $syncGoal)
                } header: { Text("同步设置") } footer: {
                    Text("这些选项决定导出 JSON 包含哪些内容，选择会保存在本机。提示音和模式参数默认关闭，目标日期默认开启。导入按文件内容合并，不受本机开关影响；计时接续需在导入时单独确认。")
                }
                Section("提示音 · 内置声音") {
                    ForEach(PhoneSounds.presets) { sound in
                        HStack { Text(sound.name); Spacer(); preview(sound) }
                    }
                }
                Section {
                    Text("导入即保存音频，点击名称可重命名。支持常见音频格式，最大 50 MB。删除仅影响本机，旧导出文件仍可重新导入。声音受静音与系统音量影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = sounds.error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                    do { try sounds.add(result.get()) } catch { sounds.error = "导入失败：\(error.localizedDescription)" }
                }
                .alert("删除自定义提示音？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("取消", role: .cancel) { deleting = nil }
                    Button("删除", role: .destructive) { if let deleting { _ = store.deleteCustomSound(deleting.id) }; deleting = nil }
                } message: { Text("将删除“\(deleting?.name ?? "")”及本机音频文件，使用它的提醒恢复默认声音。") }
                .alert("提示音名称", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
                    TextField("名称", text: $name)
                    Button("取消", role: .cancel) { renameID = nil }
                    Button("保存") { if let id = renameID { sounds.rename(id, name: name) }; renameID = nil }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).count > 80)
                }
        }
    }
    private func preview(_ sound: PhoneSound) -> some View {
        Button { sounds.play(sound.id) } label: { Image(systemName: "play.circle").font(.title3).frame(width: 44, height: 44) }
            .buttonStyle(.borderless).accessibilityLabel("试听" + sound.name)
    }
}
