import SwiftUI
import UniformTypeIdentifiers
import FocusCountCore

struct ExchangeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DataExchangeView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var document = ExchangeDocument(data: Data())
    @State private var incoming: Database?
    @State private var message: String?
    @State private var showVersions = false
    @State private var restoring: SessionSnapshot?
    private var versioned: [StudySession] { store.database.sessions.filter { !($0.history ?? []).isEmpty }.sorted { $0.startedAt > $1.startedAt } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button { dismiss() } label: { Label("返回计时", systemImage: "arrow.left") }
                    .buttonStyle(.borderedProminent).tint(.teal).keyboardShortcut(.cancelAction)
                Text("数据管理").font(.title2.bold())
                Spacer()
                Button("打开备份目录") {
                    do {
                        let directory = try Storage.directory.appendingPathComponent("backups")
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    } catch { message = error.localizedDescription }
                }
            }
            HStack {
                Text("数据保存在这台 Mac 的应用数据目录。").foregroundStyle(.secondary)
                Spacer()
                Button("打开数据目录") {
                    do {
                        let directory = Storage.directory
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    } catch { message = error.localizedDescription }
                }
            }
            Text("与 iPhone 交换 JSON，自动合并记录并保留不同版本。")
                .foregroundStyle(.secondary)
            HStack {
                Button { importing = true } label: { Label("导入并合并", systemImage: "square.and.arrow.down") }.disabled(store.blocked)
                Button {
                    do { document = ExchangeDocument(data: try store.export()); exporting = true }
                    catch { message = error.localizedDescription }
                } label: { Label("导出 JSON", systemImage: "square.and.arrow.up") }.disabled(store.blocked)
                Spacer()
                Toggle("历史版本", isOn: $showVersions).toggleStyle(.button)
            }
            if let incoming {
                let merged = RecordExchange.merge(local: store.database.sessions, incoming: incoming.sessions, purgedIDs: (store.database.purgedIDs ?? []).union(incoming.purgedIDs ?? []))
                GroupBox("导入预览") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("文件包含 \(incoming.events?.count ?? 0) 个时间标记，随记录一起合并。")
                        Text("文件中 \(incoming.sessions.count) 条记录 · 合并后 \(merged.count) 条（含最近删除）")
                        Text("合并后保留 \(RecordExchange.archivedCount(merged)) 个历史版本，不重复计入统计。")
                        Text("彻底删除标记会同步清除对应记录及其历史版本。修改时间较新的版本作为当前记录；时间相同按固定规则选定，两端结果一致。其他版本保留，可恢复。导入前备份双方数据，不替换当前计时。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("取消") { self.incoming = nil }
                            Spacer()
                            Button("确认合并") {
                                if store.importRecords(incoming) { self.incoming = nil; message = "合并完成，备份与历史版本已保留。" }
                            }.buttonStyle(.borderedProminent).tint(.teal)
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if showVersions {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if versioned.isEmpty { Text("暂无历史版本。不同版本合并或编辑记录后会自动保留。").foregroundStyle(.secondary) }
                        ForEach(versioned) { session in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("\(session.subject) · \(session.startedAt.formatted(date: .abbreviated, time: .shortened))").font(.headline)
                                    Text("当前：\(duration(session.activeSeconds)) · \(session.focus)\(session.deletedAt == nil ? "" : " · 已删除")").font(.caption).foregroundStyle(.secondary)
                                    ForEach((session.history ?? []).sorted { RecordExchange.modified($0.session) > RecordExchange.modified($1.session) }) { snapshot in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("\(snapshot.subject) · \(duration(snapshot.activeSeconds)) · \(snapshot.focus)\(snapshot.deletedAt == nil ? "" : " · 已删除")")
                                                Text("\(snapshot.startedAt.formatted(date: .abbreviated, time: .shortened)) — \(snapshot.endedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                                                Text("修改于 \(RecordExchange.modified(snapshot.session).formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button("恢复此版本") { restoring = snapshot }.disabled(store.blocked)
                                        }
                                    }
                                }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("相同 ID 自动去重，往返导入不会重复累计", systemImage: "checkmark.circle")
                    Label("不同修改保留为历史版本，支持恢复", systemImage: "clock.arrow.circlepath")
                    Label("导入前完整备份，当前计时保持不变", systemImage: "externaldrive")
                }.foregroundStyle(.secondary).padding(.top, 8)
                Spacer()
            }
            if let message { Text(message).font(.callout).textSelection(.enabled) }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("需要手动选择文件导入；此功能不自动联网同步。两端请都更新到支持 v5 的版本。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 720, height: 650)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else {
                    throw RecordExchange.ExchangeError.invalid("文件超过 20 MB，请先缩小文件。")
                }
                incoming = try RecordExchange.decode(Data(contentsOf: url)); message = nil
            } catch { incoming = nil; message = "导入失败：\(error.localizedDescription)" }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "FocusCount-sessions") { result in
            switch result {
            case .success: message = "JSON 已导出，包含当前记录、删除标记及全部历史版本。"
            case .failure(let error): message = "导出失败：\(error.localizedDescription)"
            }
        }
        .alert("恢复此历史版本？", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("取消", role: .cancel) { restoring = nil }
            Button("恢复") {
                if let restoring, store.restoreVersion(restoring) { message = "已恢复，之前的当前版本仍保留在历史中。" }
                restoring = nil
            }
        } message: { Text("恢复会更新科目、时间、专注度及删除状态，同时保留当前版本。") }
    }
}
