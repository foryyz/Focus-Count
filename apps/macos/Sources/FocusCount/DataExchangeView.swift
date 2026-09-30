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
    @State private var syncTimer = false
    @AppStorage(SyncPreferences.soundsKey) private var syncSounds = false
    @AppStorage(SyncPreferences.parametersKey) private var syncParameters = false
    @State private var archives: [ImportArchive] = []
    @State private var importing = false
    @State private var exporting = false
    @State private var document = ExchangeDocument(data: Data())
    @State private var incoming: Database?
    @State private var message: String?
    @State private var showVersions = false
    @State private var restoring: SessionSnapshot?
    @State private var deletingArchive: ImportArchive?
    @State private var deletingVersion: SessionSnapshot?
    @State private var deletingAll = false
    private var versioned: [StudySession] { store.database.sessions.filter { !($0.history ?? []).isEmpty }.sorted { $0.startedAt > $1.startedAt } }
    var body: some View {
        ScrollView {
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
                if let incoming, !showVersions {
                    GroupBox("导入预览") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(ExchangePreview.source(incoming)).font(.caption).foregroundStyle(.secondary)
                            ForEach(store.importPreview(incoming, syncParameters: syncParameters, syncSounds: syncSounds), id: \.self) { Text($0) }
                            Text(ExchangePreview.rules).font(.caption).foregroundStyle(.secondary)
                            if let timer = incoming.timerTransfer {
                                Toggle("同步计时状态：\(timer.status)", isOn: $syncTimer)
                                if syncTimer { Text("替换本机计时并接续已过时间；原设备不会自动停止。") .font(.caption).foregroundStyle(.orange) }
                                if syncTimer && !syncParameters { Text("本轮按原节奏接续，下轮沿用本机参数。").font(.caption).foregroundStyle(.secondary) }
                            }
                            HStack {
                                Button("取消") { self.incoming = nil }
                                Spacer()
                                Button("确认合并") {
                                    let sessionIDs = Set(store.database.sessions.map(\.id))
                                    let eventIDs = Set((store.database.events ?? []).map(\.id))
                                    if store.importRecords(incoming, syncTimer: syncTimer, syncSounds: syncSounds, syncParameters: syncParameters) {
                                        let addedSessions = store.database.sessions.filter { !sessionIDs.contains($0.id) }.count
                                        let addedEvents = (store.database.events ?? []).filter { !eventIDs.contains($0.id) }.count
                                        self.incoming = nil
                                        message = "合并完成，新增 \(addedSessions + addedEvents) 个（专注 \(addedSessions)，标记 \(addedEvents)）。已按所选项目同步，可在历史版本查看本次备份。"
                                        archives = (try? store.importArchives()) ?? []
                                    }
                                }.buttonStyle(.borderedProminent).tint(.teal)
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if showVersions {
                    VStack {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("导入历史").font(.headline)
                                Spacer()
                                Button(role: .destructive) { deletingAll = true } label: { Label("删除全部历史版本", systemImage: "trash") }
                                .disabled(store.blocked || (archives.isEmpty && versioned.isEmpty))
                            }
                            ForEach(archives) { archive in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(archive.title)
                                        Text("备份文件修改于 " + archive.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("查看并合并") {
                                        do {
                                            incoming = try archive.read(); showVersions = false
                                            syncTimer = false
                                        } catch { message = "备份读取失败：\(error.localizedDescription)" }
                                    }.disabled(store.blocked)
                                    Button(role: .destructive) { deletingArchive = archive } label: { Image(systemName: "trash") }
                                        .help("删除此备份").accessibilityLabel("删除此备份").disabled(store.blocked)
                                }
                            }
                            Text("备份会重新进入导入预览；合并不会撤销永久删除。").font(.caption).foregroundStyle(.secondary)
                            Text("记录修改版本").font(.headline)
                            if versioned.isEmpty { Text("暂无记录修改版本。仅新增数据不会产生旧修改，请查看上方导入历史。").foregroundStyle(.secondary) }
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
                                                Button(role: .destructive) { deletingVersion = snapshot } label: { Image(systemName: "trash") }
                                                    .help("删除此旧版本").accessibilityLabel("删除此旧版本").disabled(store.blocked)
                                            }
                                        }
                                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                } else if incoming == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("相同 ID 自动去重，往返导入不会重复累计", systemImage: "checkmark.circle")
                        Label("不同修改保留为历史版本，支持恢复", systemImage: "clock.arrow.circlepath")
                        Label("导入前完整备份，计时状态可选同步", systemImage: "externaldrive")
                    }.foregroundStyle(.secondary).padding(.top, 8)
                    Spacer()
                }
                if let message { Text(message).font(.callout).textSelection(.enabled) }
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
                Text("需要手动选择文件导入；此功能不自动联网同步。完整同步需将两端更新到最新版。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(width: 720, height: 780)
        .onAppear { do { archives = try store.importArchives() } catch { message = "历史读取失败：\(error.localizedDescription)" } }
        .onChange(of: showVersions) { _ in
            do { archives = try store.importArchives() } catch { message = "历史读取失败：\(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 512_000_000 else {
                    throw RecordExchange.ExchangeError.invalid("同步文件超过 512 MB，请减少自定义音频后重试。")
                }
                incoming = try RecordExchange.decode(Data(contentsOf: url)); message = nil; syncTimer = false; showVersions = false
            } catch { incoming = nil; message = "导入失败：\(error.localizedDescription)" }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "FocusCount-sessions") { result in
            switch result {
            case .success: message = "JSON 已导出，包含当前记录、删除标记及全部历史版本。"
            case .failure(let error): message = "导出失败：\(error.localizedDescription)"
            }
        }
        .alert("删除全部历史版本？", isPresented: $deletingAll) {
            Button("取消", role: .cancel) {}
            Button("全部删除", role: .destructive) {
                let success = store.deleteAllHistory()
                do { archives = try store.importArchives() } catch { message = error.localizedDescription }
                deletingArchive = nil; deletingVersion = nil; restoring = nil
                incoming = nil
                if success { message = "全部历史版本已删除。" }
            }
        } message: {
            Text("将永久删除本机全部 \(archives.count) 份导入备份及 \(RecordExchange.archivedCount(store.database.sessions)) 个记录旧版本。当前记录、最近删除中的记录和计时状态均保留。旧版本删除标记随数据同步，此操作无法撤销。")
        }
        .alert("删除此历史版本？", isPresented: Binding(get: { deletingArchive != nil || deletingVersion != nil }, set: { if !$0 { deletingArchive = nil; deletingVersion = nil } })) {
            Button("取消", role: .cancel) { deletingArchive = nil; deletingVersion = nil }
            Button("删除", role: .destructive) {
                if let archive = deletingArchive, store.deleteArchive(archive) {
                    do { archives = try store.importArchives() } catch { message = error.localizedDescription }
                    incoming = nil
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
            Button("恢复") {
                if let restoring, store.restoreVersion(restoring) { message = "已恢复，之前的当前版本仍保留在历史中。" }
                restoring = nil
            }
        } message: { Text("恢复会更新科目、时间、专注度及删除状态，同时保留当前版本。") }
    }
}
