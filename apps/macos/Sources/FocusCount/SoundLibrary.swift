import FocusCountCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FocusSound: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var file: String?
    var modified: Date?
}

@MainActor final class SoundLibrary: ObservableObject {
    static let shared = SoundLibrary()
    static let builtins = [FocusSound(id: "Glass", name: "清脆 · Glass"), FocusSound(id: "Pop", name: "轻点 · Pop"), FocusSound(id: "Hero", name: "明亮 · Hero"), FocusSound(id: "Ping", name: "叮咚 · Ping"), FocusSound(id: "Tink", name: "轻铃 · Tink"), FocusSound(id: "Submarine", name: "水滴 · Submarine")]
    @Published private(set) var custom: [FocusSound] = []
    @Published var error: String?
    private let root: URL?
    var sounds: [FocusSound] { Self.builtins + custom }
    init(directory: URL? = nil) {
        root = directory ?? (try? Storage.directory.appendingPathComponent("sounds", isDirectory: true))
        guard let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("library.json").path) else { return }
        do { custom = try JSONDecoder().decode([FocusSound].self, from: Data(contentsOf: root.appendingPathComponent("library.json"))) }
        catch { self.error = "无法读取提示音库：\(error.localizedDescription)" }
    }
    private func save(_ items: [FocusSound]) throws {
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: root.appendingPathComponent("library.json"), options: .atomic)
        custom = items
    }
    func sound(_ id: String) -> NSSound? {
        if Self.builtins.contains(where: { $0.id == id }) { return NSSound(named: NSSound.Name(id)) }
        guard let entry = custom.first(where: { $0.id == id }), let file = entry.file,
              file == URL(fileURLWithPath: file).lastPathComponent, let root else { return nil }
        return NSSound(contentsOf: root.appendingPathComponent(file), byReference: false)
    }
    func importSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.message = "选择提示音文件；导入后可自定义名称。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try add(url) } catch { self.error = "导入失败：\(error.localizedDescription)" }
    }
    func add(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 50 * 1024 * 1024, NSSound(contentsOf: url, byReference: false) != nil else {
            throw NSError(domain: "FocusSound", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择可播放的音频文件（不超过 50 MB）。"])
        }
        let id = UUID().uuidString
        let file = id + "." + url.pathExtension
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(file)
        try FileManager.default.copyItem(at: url, to: destination)
        do { try save(custom + [FocusSound(id: id, name: url.deletingPathExtension().lastPathComponent, file: file)]) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    func exportSounds() throws -> [SharedSound] {
        guard let folder = root else { throw CocoaError(.fileNoSuchFile) }
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
        guard let folder = root else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let previous = custom
        var next = custom
        var files: [String: Data] = [:]
        for sound in incoming {
            guard sound.isValid else { throw CocoaError(.fileReadCorruptFile) }
            if let old = next.first(where: { $0.id == sound.id }), (old.modified ?? .distantPast) > sound.modified || ((old.modified ?? .distantPast) == sound.modified && old.name > sound.name) { continue }
            let file = sound.id + "." + sound.fileExtension
            guard NSSound(data: sound.data) != nil else { throw CocoaError(.fileReadCorruptFile) }
            files[file] = sound.data
            let entry = FocusSound(id: sound.id, name: sound.name, file: file, modified: sound.modified)
            next.removeAll { $0.id == sound.id }; next.append(entry)
        }
        let transaction = try SoundFileTransaction(directory: folder, files: files, index: JSONEncoder().encode(next)) { [weak self] in self?.custom = previous }
        custom = next
        return transaction
    }
    func rename(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = custom.firstIndex(where: { $0.id == id }) else { return }
        var items = custom; items[index].name = String(name.prefix(80)); items[index].modified = Date()
        do { try save(items) } catch { self.error = "保存名称失败：\(error.localizedDescription)" }
    }
}

struct SoundSettingsView: View {
    @ObservedObject var store: StudyStore
    @ObservedObject private var library = SoundLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    @AppStorage(SyncPreferences.soundsKey) private var syncSounds = false
    @AppStorage(SyncPreferences.parametersKey) private var syncParameters = false
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("设置").font(.headline); Spacer(); Button("完成") { dismiss() } }.padding(20)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<2) { index in
                        Button { section = index } label: {
                            Label(index == 0 ? "提示音" : "同步设置", systemImage: index == 0 ? "speaker.wave.2" : "arrow.triangle.2.circlepath")
                                .font(.callout.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(section == index ? Color.teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(8).frame(width: 140)
                Divider()
                ScrollView {
                    if section == 1 {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("同步设置").font(.headline)
                            Toggle("同步自定义提示音与声音设置", isOn: $syncSounds)
                            Toggle("同步模式数值参数", isOn: $syncParameters)
                            Text("默认关闭。选择会保存在本机，并用于之后每次导入；计时状态仍在导入时单独选择。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("内置提示音").font(.headline)
                            ForEach(SoundLibrary.builtins) { sound in
                                HStack { Text(sound.name); Spacer(); Button("试听") { store.previewModeSound(id: sound.id) } }
                            }
                            Divider()
                            HStack { Text("我的提示音").font(.headline); Spacer(); Button("导入音频…") { library.importSound() } }
                            ForEach(library.custom) { sound in SoundNameRow(sound: sound, store: store) }
                            Text("点击自定义名称编辑，回车或点击保存。音频会复制到本机数据目录，不依赖原文件；导入其他设备的提示音可在“同步设置”中开启。")
                                .font(.caption).foregroundStyle(.secondary)
                            if let error = library.error { Text(error).font(.caption).foregroundStyle(.red) }
                        }.padding(20)
                    }
                }
            }
        }.frame(width: 600, height: 460)
    }
}

private struct SoundNameRow: View {
    let sound: FocusSound
    @ObservedObject var store: StudyStore
    @State private var name = ""
    var body: some View {
        HStack {
            TextField("提示音名称", text: $name).onSubmit { SoundLibrary.shared.rename(sound.id, to: name) }
            Button("保存") { SoundLibrary.shared.rename(sound.id, to: name) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("试听") { store.previewModeSound(id: sound.id) }
        }.onAppear { name = sound.name }
    }
}
