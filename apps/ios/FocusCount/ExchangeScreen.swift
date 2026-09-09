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
    @State private var showVersions = false
    private var added: Int { pending?.sessions.filter { record in !store.state.sessions.contains { $0.id == record.id } }.count ?? 0 }
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
                Section {
                    Button { showVersions = true } label: { Label("历史版本与恢复", systemImage: "clock.arrow.circlepath") }
                } footer: { Text("不同修改会保留为历史版本，不重复计入统计。两端都需更新到支持 v3 的版本。") }
                if let pending {
                    Section("导入预览") {
                        LabeledContent("文件记录", value: "\(pending.sessions.count) 条")
                        LabeledContent("新增", value: "\(added) 条")
                        LabeledContent("合并后历史版本", value: "\(RecordExchange.archivedCount(RecordExchange.merge(local: store.state.sessions, incoming: pending.sessions))) 个")
                        Text("相同 ID 自动去重，以修改时间较新者为当前记录；同时间按固定规则选定，两端结果一致。其他版本保留可恢复。导入前备份双方数据。")
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
            .sheet(isPresented: $showVersions) { PhoneVersionHistory(store: store) }
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


struct PhoneVersionHistory: View {
    @ObservedObject var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    @State private var restoring: SessionSnapshot?
    private var records: [StudySession] { store.state.sessions.filter { !($0.history ?? []).isEmpty }.sorted { $0.startedAt > $1.startedAt } }
    var body: some View {
        NavigationStack {
            List {
                if records.isEmpty { ContentUnavailableView("暂无历史版本", systemImage: "clock.arrow.circlepath", description: Text("编辑或合并不同版本后会自动保留。")) }
                ForEach(records) { session in
                    Section {
                        Text("当前：\(phoneDuration(session.activeSeconds)) · \(session.focus)\(session.deletedAt == nil ? "" : " · 已删除")").font(.caption).foregroundStyle(.secondary)
                        ForEach((session.history ?? []).sorted { RecordExchange.modified($0.session) > RecordExchange.modified($1.session) }) { snapshot in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(snapshot.subject) · \(phoneDuration(snapshot.activeSeconds)) · \(snapshot.focus)").font(.headline)
                                Text("\(snapshot.startedAt.formatted(date: .abbreviated, time: .shortened)) — \(snapshot.endedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                                Text("修改于 \(RecordExchange.modified(snapshot.session).formatted(date: .abbreviated, time: .standard))\(snapshot.deletedAt == nil ? "" : " · 已删除")").font(.caption).foregroundStyle(.secondary)
                                Button("恢复此版本") { restoring = snapshot }.disabled(store.blocked)
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("\(session.subject) · \(session.startedAt.formatted(date: .abbreviated, time: .shortened))") }
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("历史版本").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .alert("恢复此历史版本？", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
                    Button("取消", role: .cancel) { restoring = nil }
                    Button("恢复") { if let restoring { store.restoreVersion(restoring) }; restoring = nil }
                } message: { Text("恢复科目、时间、专注度及删除状态，当前版本也会保留。") }
        }
    }
}
