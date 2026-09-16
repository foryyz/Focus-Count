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
    @State private var reading = false
    @State private var filename = ""
    @State private var showResult = false
    private var merged: [StudySession] {
        guard let pending else { return store.state.sessions }
        return RecordExchange.merge(local: store.state.sessions, incoming: pending.sessions,
            purgedIDs: (store.state.purgedIDs ?? []).union(pending.purgedIDs ?? []))
    }
    private var added: Int { pending?.sessions.filter { record in !(store.state.purgedIDs ?? []).contains(record.id) && !store.state.sessions.contains { $0.id == record.id } }.count ?? 0 }
    var body: some View {
        NavigationStack {
            Form {
                if reading { Section { ProgressView("正在读取文件…") } }
                if let failure { Section("读取失败") { Text(failure).foregroundStyle(.red) } }
                if let pending {
                    Section("请确认导入 · 尚未写入") {
                        Text(filename).font(.headline)
                        Text("文件包含 \(pending.events?.count ?? 0) 个时间标记，随记录一起合并。")
                        LabeledContent("文件记录", value: "\(pending.sessions.count) 条")
                        LabeledContent("新增记录（含最近删除）", value: "\(added) 条")
                        LabeledContent("合并后学习记录", value: "\(merged.filter { $0.deletedAt == nil }.count) 条")
                        LabeledContent("合并后最近删除", value: "\(merged.filter { $0.deletedAt != nil }.count) 条")
                        LabeledContent("合并后历史版本", value: "\(RecordExchange.archivedCount(merged)) 个")
                        Text("相同记录不会重复新增；较旧修改保留在历史版本中。彻底删除过的记录不会重新出现。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button {
                            let before = store.state.sessions
                            if store.importRecords(pending) {
                                let after = store.state.sessions
                                let addedCount = after.filter { record in !before.contains { $0.id == record.id } }.count
                                let changedCount = after.filter { record in
                                    before.contains { $0.id == record.id && SessionSnapshot($0) != SessionSnapshot(record) }
                                }.count
                                let removedCount = before.filter { record in !after.contains { $0.id == record.id } }.count
                                message = "新增 \(addedCount) 条，更新 \(changedCount) 条，彻底删除 \(removedCount) 条。\n当前学习记录 \(store.sessions.count) 条，最近删除 \(after.count - store.sessions.count) 条，历史版本 \(RecordExchange.archivedCount(after)) 个。\n相同记录不重复新增，较旧修改请在历史版本中查看。"
                                self.pending = nil
                                showResult = true
                            } else { failure = store.error ?? "导入未完成，请重试。" }
                        } label: {
                            Text("确认合并到 iPhone").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }.buttonStyle(.borderedProminent).disabled(store.blocked)
                        Button("取消导入", role: .cancel) { self.pending = nil }
                    }
                }

                Section {
                    Label("数据保存在这台 iPhone", systemImage: "iphone")
                    Text("无需账号，离线可用。通过 JSON 文件与电脑交换记录，当前不会自动同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button { pending = nil; failure = nil; message = nil; importing = true } label: { Label("导入 JSON", systemImage: "square.and.arrow.down") }.disabled(store.blocked || reading)
                    Button {
                        do { document = JSONDocument(data: try store.export()); exporting = true }
                        catch { failure = error.localizedDescription }
                    } label: { Label("导出 JSON", systemImage: "square.and.arrow.up") }.disabled(store.blocked)
                } footer: { Text("兼容 Mac 的 sessions.json。导入只合并记录，不接管其他设备的计时草稿；导出包含已删除标记。") }
                Section {
                    Button { showVersions = true } label: { Label("历史版本与恢复", systemImage: "clock.arrow.circlepath") }
                } footer: { Text("不同修改会保留为历史版本，不重复计入统计。两端都需更新到支持 v5 的版本。") }
                if let message { Section { Text(message).foregroundStyle(.teal) } }
                if let error = store.error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .id(pending != nil) // Reset the form scroll position when a file is ready.
            .navigationTitle("数据管理").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(pending == nil ? "完成" : "取消并关闭") { dismiss() }.disabled(reading) } }
            .sheet(isPresented: $showVersions) { PhoneVersionHistory(store: store) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    filename = url.lastPathComponent
                    reading = true
                    Task {
                        do {
                            let data = try await Task.detached { try PhoneImportFile.read(url) }.value
                            pending = try RecordExchange.decode(data)
                            failure = nil; message = nil
                        } catch {
                            pending = nil
                            failure = "导入失败：\(error.localizedDescription)"
                        }
                        reading = false
                    }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError {
                        failure = "无法选择文件：\(error.localizedDescription)"
                    }
                }
            }
            .alert("导入完成", isPresented: $showResult) {
                Button("好", role: .cancel) {}
            } message: { Text(message ?? "") }
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
