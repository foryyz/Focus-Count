import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UserNotifications

struct PhoneSound: Codable, Identifiable {
    let id: String
    var name: String
    var file: String?
}

@MainActor final class PhoneSounds: ObservableObject {
    static let shared = PhoneSounds()
    static let presets = [PhoneSound(id: "Glass", name: "清脆"), PhoneSound(id: "Pop", name: "轻点"), PhoneSound(id: "Hero", name: "明亮"), PhoneSound(id: "Ping", name: "叮咚"), PhoneSound(id: "Tink", name: "轻铃"), PhoneSound(id: "Submarine", name: "水滴")]
    @Published private(set) var custom: [PhoneSound] = []
    @Published var error: String?
    private var player: AVAudioPlayer?
    let directory: URL
    var sounds: [PhoneSound] { Self.presets + custom }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FocusCount/sounds")
        let index = self.directory.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: index.path) {
            do { custom = try JSONDecoder().decode([PhoneSound].self, from: Data(contentsOf: index)) }
            catch { self.error = "提示音库读取失败：\(error.localizedDescription)" }
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
        if !FileManager.default.fileExists(atPath: destination.path) {
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
                let id = UUID().uuidString, file = UUID().uuidString + "." + source.pathExtension
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(file)
                try FileManager.default.copyItem(at: source, to: destination)
                do { try save(custom + [PhoneSound(id: id, name: String(source.deletingPathExtension().lastPathComponent.prefix(80)), file: file)]) }
                catch { try? FileManager.default.removeItem(at: destination); throw error }
            }
        }
        if let failure { throw failure }
        guard let outcome else { throw CocoaError(.fileReadUnknown) }
        try outcome.get()
    }
    func rename(_ id: String, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = custom.firstIndex(where: { $0.id == id }) else { return }
        var items = custom; items[index].name = String(name.prefix(80))
        do { try save(items) } catch { self.error = "名称保存失败：\(error.localizedDescription)" }
    }
}

struct PhoneSoundSettings: View {
    @ObservedObject private var sounds = PhoneSounds.shared
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var renameID: String?
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                Section("提示音 · 内置声音") {
                    ForEach(PhoneSounds.presets) { sound in
                        HStack { Text(sound.name); Spacer(); preview(sound) }
                    }
                }
                Section("我的提示音") {
                    Button { importing = true } label: { Label("导入音频", systemImage: "plus.circle") }
                    ForEach(sounds.custom) { sound in
                        HStack {
                            Button(sound.name) { name = sound.name; renameID = sound.id }.foregroundStyle(.primary)
                            Spacer(); preview(sound)
                        }
                    }
                }
                Section {
                    Text("点击自定义声音的名称即可重命名。支持常见音频格式，最大 50 MB；音频复制到本机，暂不随记录导出。声音受静音开关和系统音量影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = sounds.error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle("提示音设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                    do { try sounds.add(result.get()) } catch { sounds.error = "导入失败：\(error.localizedDescription)" }
                }
                .alert("提示音名称", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
                    TextField("名称", text: $name)
                    Button("取消", role: .cancel) { renameID = nil }
                    Button("保存") { if let id = renameID { sounds.rename(id, name: name) }; renameID = nil }
                }
        }
    }
    private func preview(_ sound: PhoneSound) -> some View {
        Button { sounds.play(sound.id) } label: { Image(systemName: "play.circle").font(.title3).frame(width: 44, height: 44) }
            .buttonStyle(.borderless).accessibilityLabel("试听" + sound.name)
    }
}
