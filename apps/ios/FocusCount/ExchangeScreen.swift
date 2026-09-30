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
    var initialImport: Database? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var syncTimer = false
    @AppStorage(SyncPreferences.soundsKey) private var syncSounds = false
    @AppStorage(SyncPreferences.parametersKey) private var syncParameters = false
    @State private var importing = false
    @State private var exporting = false
    @State private var document = JSONDocument(data: Data())
    @State private var pending: Database?
    @State private var message: String?
    @State private var failure: String?
    @State private var showVersions = false
    @State private var reading = false
    @State private var didLoadInitial = false
    @State private var filename = ""
    @State private var showResult = false
    var body: some View {
        NavigationStack {
            Form {
                if reading { Section { ProgressView("正在读取文件…") } }
                if let failure { Section("读取失败") { Text(failure).foregroundStyle(.red) } }
                if let pending {
                    Section("请确认导入 · 尚未写入") {
                        Text(filename).font(.headline)
                        Text(ExchangePreview.source(pending)).font(.footnote).foregroundStyle(.secondary)
                        ForEach(store.importPreview(pending, syncParameters: syncParameters, syncSounds: syncSounds), id: \.self) { Text($0) }
                        Text(ExchangePreview.rules).font(.footnote).foregroundStyle(.secondary)
                        if let timer = pending.timerTransfer {
                            Toggle("同步计时状态：\(timer.status)", isOn: $syncTimer)
                            if syncTimer { Text("替换本机计时并接续已过时间；原设备不会自动停止。") .font(.footnote).foregroundStyle(.orange) }
                            if syncTimer && !syncParameters { Text("本轮按原节奏接续，下轮沿用本机参数。").font(.caption).foregroundStyle(.secondary) }
                        }
                        Button {
                            let changes = store.importPreview(pending, syncParameters: syncParameters, syncSounds: syncSounds)
                            if store.importRecords(pending, syncTimer: syncTimer, syncSounds: syncSounds, syncParameters: syncParameters) {
                                message = (["合并完成，已按所选项目同步。"] + changes + ["本次备份可在历史版本查看。"]).joined(separator: "\n")
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
                } footer: { Text("交换记录、标记与个性化设置。提示音与模式参数按“设置 → 同步设置”执行；计时可在本页选择。") }
                Section {
                    Button { showVersions = true } label: { Label("历史版本与恢复", systemImage: "clock.arrow.circlepath") }
                } footer: { Text("查看历次导入备份和记录旧修改，不重复计入统计。") }
                if let message { Section { Text(message).foregroundStyle(.teal) } }
                if let error = store.error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .onAppear {
                guard !didLoadInitial else { return }
                didLoadInitial = true
                if let initialImport { pending = initialImport; filename = "历史备份" }
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
                            syncTimer = false
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
    @State private var deletingArchive: ImportArchive?
    @State private var deletingVersion: SessionSnapshot?
    @State private var deletingAll = false
    @State private var archives: [ImportArchive] = []
    @State private var archiveDatabase: Database?
    @State private var previewBackup = false
    @State private var archiveError: String?
    private var records: [StudySession] { store.state.sessions.filter { !($0.history ?? []).isEmpty }.sorted { $0.startedAt > $1.startedAt } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) { deletingAll = true } label: { Label("删除全部历史版本", systemImage: "trash") }
                        .disabled(store.blocked || (archives.isEmpty && records.isEmpty))
                }
                Section("导入历史") {
                    if archives.isEmpty { Text("暂无导入备份").foregroundStyle(.secondary) }
                    ForEach(archives) { archive in
                        HStack {
                            Button {
                                do { archiveDatabase = try archive.read(); previewBackup = true }
                                catch { archiveError = "备份读取失败：\(error.localizedDescription)" }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(archive.title)
                                    Text("备份文件修改于 " + archive.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                                    Text("查看并合并").font(.caption)
                                }
                            }.buttonStyle(.borderless)
                            Spacer()
                            Button(role: .destructive) { deletingArchive = archive } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("删除此备份")
                        }.disabled(store.blocked)
                    }
                    Text("备份会重新进入导入预览；合并不会撤销永久删除。").font(.caption).foregroundStyle(.secondary)
                }
                if let archiveError { Text(archiveError).foregroundStyle(.red) }
                if records.isEmpty { Text("暂无记录修改版本。仅新增数据不会产生旧修改，请查看上方导入历史。").foregroundStyle(.secondary) }
                ForEach(records) { session in
                    Section {
                        Text("当前：\(phoneDuration(session.activeSeconds)) · \(session.focus)\(session.deletedAt == nil ? "" : " · 已删除")").font(.caption).foregroundStyle(.secondary)
                        ForEach((session.history ?? []).sorted { RecordExchange.modified($0.session) > RecordExchange.modified($1.session) }) { snapshot in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(snapshot.subject) · \(phoneDuration(snapshot.activeSeconds)) · \(snapshot.focus)").font(.headline)
                                Text("\(snapshot.startedAt.formatted(date: .abbreviated, time: .shortened)) — \(snapshot.endedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                                Text("修改于 \(RecordExchange.modified(snapshot.session).formatted(date: .abbreviated, time: .standard))\(snapshot.deletedAt == nil ? "" : " · 已删除")").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("恢复此版本") { restoring = snapshot }.buttonStyle(.borderless)
                                    Spacer()
                                    Button(role: .destructive) { deletingVersion = snapshot } label: { Label("删除", systemImage: "trash") }.buttonStyle(.borderless)
                                }.disabled(store.blocked)
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("\(session.subject) · \(session.startedAt.formatted(date: .abbreviated, time: .shortened))") }
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }
                .onAppear { do { archives = try store.importArchives() } catch { archiveError = error.localizedDescription } }
                .sheet(isPresented: $previewBackup, onDismiss: { do { archives = try store.importArchives() } catch { archiveError = error.localizedDescription } }) {
                    ExchangeScreen(store: store, initialImport: archiveDatabase)
                }
                .navigationTitle("历史版本").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .alert("删除全部历史版本？", isPresented: $deletingAll) {
                    Button("取消", role: .cancel) {}
                    Button("全部删除", role: .destructive) {
                        let success = store.deleteAllHistory()
                        do { archives = try store.importArchives() } catch { archiveError = error.localizedDescription }
                        deletingArchive = nil; deletingVersion = nil; restoring = nil
                        archiveDatabase = nil
                        if success { archiveError = nil }
                    }
                } message: {
                    Text("将永久删除本机全部 \(archives.count) 份导入备份及 \(RecordExchange.archivedCount(store.state.sessions)) 个记录旧版本。当前记录、最近删除中的记录和计时状态均保留。旧版本删除标记随数据同步，此操作无法撤销。")
                }
                .alert("删除此历史版本？", isPresented: Binding(get: { deletingArchive != nil || deletingVersion != nil }, set: { if !$0 { deletingArchive = nil; deletingVersion = nil } })) {
                    Button("取消", role: .cancel) { deletingArchive = nil; deletingVersion = nil }
                    Button("删除", role: .destructive) {
                        if let archive = deletingArchive, store.deleteArchive(archive) {
                            do { archives = try store.importArchives() } catch { archiveError = error.localizedDescription }
                            archiveDatabase = nil
                        }
                        if let snapshot = deletingVersion { _ = store.deleteVersion(snapshot) }
                        deletingArchive = nil; deletingVersion = nil
                    }
                } message: {
                    Text(deletingArchive != nil
                        ? "将永久删除这份本机备份文件，不影响当前记录或其他备份。"
                        : "将永久删除这条旧修改，不影响当前记录。删除标记随数据同步，旧文件不会重新带回该版本。")
                }
                .alert("恢复此历史版本？", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
                    Button("取消", role: .cancel) { restoring = nil }
                    Button("恢复") { if let restoring { store.restoreVersion(restoring) }; restoring = nil }
                } message: { Text("恢复活动、时间、专注度及删除状态，当前版本也会保留。") }
        }
    }
}
