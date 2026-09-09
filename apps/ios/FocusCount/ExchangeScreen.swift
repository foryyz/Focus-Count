import SwiftUI
import UniformTypeIdentifiers
import FocusCountCore

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ExchangeScreen: View {
    @ObservedObject var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var document = JSONDocument(data: Data())
    @State private var pending: Database?
    @State private var message: String?
    @State private var failure: String?
    private var added: Int { pending?.sessions.filter { record in !store.state.sessions.contains { $0.id == record.id } }.count ?? 0 }
    private var updated: Int {
        pending?.sessions.filter { record in store.state.sessions.contains { $0.id == record.id && RecordExchange.modified(record) > RecordExchange.modified($0) } }.count ?? 0
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("数据保存在这台 iPhone", systemImage: "iphone")
                    Text("无需账号，离线可用。通过 JSON 文件与电脑交换记录，当前不会自动同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button { importing = true } label: { Label("导入 JSON", systemImage: "square.and.arrow.down") }.disabled(store.blocked)
                    Button {
                        do { document = JSONDocument(data: try store.export()); exporting = true }
                        catch { failure = error.localizedDescription }
                    } label: { Label("导出 JSON", systemImage: "square.and.arrow.up") }.disabled(store.blocked)
                } footer: { Text("兼容 Mac 的 sessions.json。导入只合并记录，不接管其他设备的计时草稿；导出包含已删除标记。") }
                if let pending {
                    Section("导入预览") {
                        LabeledContent("文件记录", value: "\(pending.sessions.count) 条")
                        LabeledContent("新增", value: "\(added) 条")
                        LabeledContent("更新", value: "\(updated) 条")
                        Text("相同 ID 保留修改时间较新的记录；时间相同保留手机本地记录。删除标记也会合并。导入前自动备份本地数据。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("确认合并") {
                            if store.importRecords(pending) { self.pending = nil; message = "导入完成，学习记录已更新。" }
                        }.fontWeight(.semibold)
                        Button("取消导入", role: .cancel) { self.pending = nil }
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.teal) } }
                if let failure { Section { Text(failure).foregroundStyle(.red).font(.footnote) } }
                if let error = store.error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("数据管理").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 20_000_000 else { throw RecordExchange.ExchangeError.invalid("文件超过 20 MB，请先缩小文件。") }
                    pending = try RecordExchange.decode(Data(contentsOf: url)); failure = nil; message = nil
                } catch { pending = nil; failure = "导入失败：\(error.localizedDescription)" }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "FocusCount-sessions") { result in
                switch result {
                case .success: message = "已导出 JSON 文件。"
                case .failure(let error): failure = "导出失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
