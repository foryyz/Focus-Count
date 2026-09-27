import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FocusSound: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var file: String?
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
    func rename(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = custom.firstIndex(where: { $0.id == id }) else { return }
        var items = custom; items[index].name = String(name.prefix(80))
        do { try save(items) } catch { self.error = "保存名称失败：\(error.localizedDescription)" }
    }
}

struct SoundSettingsView: View {
    @ObservedObject var store: StudyStore
    @ObservedObject private var library = SoundLibrary.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("设置").font(.headline); Spacer(); Button("完成") { dismiss() } }.padding(20)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                Label("提示音", systemImage: "speaker.wave.2").font(.callout.weight(.medium))
                    .padding(14).frame(width: 120).background(Color.teal.opacity(0.08))
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("内置提示音").font(.headline)
                        ForEach(SoundLibrary.builtins) { sound in
                            HStack { Text(sound.name); Spacer(); Button("试听") { store.previewModeSound(id: sound.id) } }
                        }
                        Divider()
                        HStack { Text("我的提示音").font(.headline); Spacer(); Button("导入音频…") { library.importSound() } }
                        ForEach(library.custom) { sound in SoundNameRow(sound: sound, store: store) }
                        Text("点击自定义名称编辑，回车或点击保存。音频会复制到本机数据目录，不依赖原文件；暂不随记录导出同步。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = library.error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.padding(20)
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
