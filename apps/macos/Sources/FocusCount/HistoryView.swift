import FocusCountCore
import SwiftUI

struct HistoryFilter {
    var start = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
    var end = Date()
    var allDates = true
    var subject = ""
    var focus = ""
    var deleted = false

    func apply(_ sessions: [StudySession], calendar: Calendar = .current) -> [StudySession] {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        return sessions.filter {
            ($0.deletedAt != nil) == deleted &&
            (allDates || ($0.startedAt >= lower && $0.startedAt < upper)) &&
            (subject.isEmpty || $0.subject == subject) && (focus.isEmpty || $0.focus == focus)
        }.sorted { $0.startedAt > $1.startedAt }
    }
}

struct HistoryView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter = HistoryFilter()
    @State private var editing: StudySession?
    @State private var deleting: StudySession?
    @State private var purging: Set<UUID> = []
    private var records: [StudySession] { filter.apply(store.database.sessions) }
    private var total: Double { records.reduce(0) { $0 + $1.activeSeconds } }
    private var days: [Date] { Array(Set(records.map { Calendar.current.startOfDay(for: $0.startedAt) })).sorted() }
    private var subjects: [String] { Array(Set(store.database.sessions.map(\.subject))).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Button { dismiss() } label: {
                    Label("返回计时", systemImage: "arrow.left")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).tint(.teal)
                .keyboardShortcut(.cancelAction).help("返回计时（Esc）")
                VStack(alignment: .leading, spacing: 4) {
                    Text("专注记录").font(.title2.bold())
                    Text("回顾每一次专注")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { FocusAnalysisWindow.shared.show(store: store) } label: { Label("专注分析", systemImage: "chart.bar.xaxis") }
                Button("时间标记") { MarkerWindowController.shared.show(store: store) }
                Button {
                    editing = StudySession(startedAt: Date().addingTimeInterval(-1800), endedAt: Date(), activeSeconds: 1800, subject: "", focus: "A")
                } label: { Label("补记", systemImage: "plus") }.disabled(store.blocked)
            }
            HStack(spacing: 14) {
                Picker("记录", selection: $filter.deleted) {
                    Text("专注记录").tag(false)
                    Text("最近删除").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                Spacer()
                Picker("活动", selection: $filter.subject) {
                    Text("全部活动").tag("")
                    ForEach(subjects, id: \.self) { Text($0).tag($0) }
                }.frame(width: 200)
                Picker("专注度", selection: $filter.focus) {
                    Text("全部").tag("")
                    ForEach(["S", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) }
                }.frame(width: 135)
            }
            HStack {
                Toggle("全部日期", isOn: $filter.allDates).toggleStyle(.checkbox)
                DatePicker("从", selection: $filter.start, displayedComponents: .date).disabled(filter.allDates)
                DatePicker("至", selection: $filter.end, displayedComponents: .date).disabled(filter.allDates)
                Button("重置筛选") { filter = HistoryFilter(deleted: filter.deleted) }
            }
            if !filter.allDates && Calendar.current.startOfDay(for: filter.start) > Calendar.current.startOfDay(for: filter.end) {
                Text("开始日期不能晚于结束日期。").foregroundStyle(.red).font(.caption)
            }
            if filter.deleted {
                HStack { Text("可恢复或彻底删除。清空全部包含筛选外的记录。"); Spacer(); Button("清空全部", role: .destructive) { purging = Set(store.database.sessions.filter { $0.deletedAt != nil }.map(\.id)) }
                    .disabled(store.blocked || !store.database.sessions.contains { $0.deletedAt != nil }) }
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 36) {
                    metric("有效专注时间", value: duration(total))
                    metric("专注次数", value: "\(records.count) 次")
                    metric("专注天数", value: "\(days.count) 天")
                }
            }
            Divider()
            HStack {
                Text(filter.deleted ? "已删除记录" : "记录明细").font(.headline)
                Spacer()
                Text("\(records.count) 条 · 按开始时间倒序").font(.caption).foregroundStyle(.secondary)
            }
            if records.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: filter.deleted ? "trash" : "calendar").font(.largeTitle)
                    Text(filter.deleted ? "没有符合筛选条件的已删除记录" : "没有符合筛选条件的专注记录")
                    Text("可以调整筛选条件，或补记一次专注。").font(.caption)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(records) { session in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.subject).font(.headline).lineLimit(1).help(session.subject)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(duration(session.activeSeconds)).monospacedDigit()
                        Text(session.focus).font(.headline).frame(width: 24)
                        if filter.deleted {
                            Button("恢复") { store.setDeleted(session.id, deleted: false) }
                            Button("彻底删除", role: .destructive) { purging = [session.id] }
                        } else {
                            Button("编辑") { editing = session }
                            Button { deleting = session } label: { Image(systemName: "trash") }
                                .help("移至最近删除")
                        }
                    }.padding(.vertical, 5).disabled(store.blocked)
                }.listStyle(.inset)
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(24).frame(width: 840, height: 740)
        .alert("彻底删除这 \(purging.count) 条记录？", isPresented: Binding(get: { !purging.isEmpty }, set: { if !$0 { purging = [] } })) {
            Button("取消", role: .cancel) { purging = [] }
            Button("彻底删除", role: .destructive) { store.permanentlyDelete(purging); purging = [] }
        } message: { Text("记录及其历史版本将从当前数据中移除，无法在应用内恢复。导入旧文件不会重新出现。已有备份文件不受影响。") }
        .sheet(item: $editing) { session in SessionEditor(store: store, session: session) }
        .alert("将这条记录移至最近删除？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                if let session = deleting { store.setDeleted(session.id, deleted: true) }
                deleting = nil
            }
        } message: { Text("删除后不再计入统计，仍可在“最近删除”中恢复。") }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit().weight(.medium))
        }
    }
}

struct SessionEditor: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State var session: StudySession
    @State private var hours = ""
    @State private var minutes = ""
    @State private var seconds = ""
    private var isNew: Bool { !store.database.sessions.contains { $0.id == session.id } }
    private var parsedDuration: Double? {
        guard let h = Double(hours), let m = Double(minutes), let s = Double(seconds),
              h.isFinite, m.isFinite, s.isFinite, h >= 0, h.rounded() == h,
              m >= 0, m < 60, m.rounded() == m, s >= 0, s < 60 else { return nil }
        return h * 3600 + m * 60 + s
    }
    private var candidate: StudySession {
        var result = session
        result.activeSeconds = parsedDuration ?? -1
        return result
    }
    private var problem: String? {
        parsedDuration == nil ? "请输入有效时长：小时为非负整数，分和秒小于 60。" : candidate.validationError
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "补记专注" : "编辑专注记录").font(.title2.bold())
            TextField("活动名称（必填）", text: $session.subject).textFieldStyle(.roundedBorder)
            if !store.subjects.isEmpty {
                Menu("选择已有活动") {
                    ForEach(store.subjects, id: \.self) { subject in Button(subject) { session.subject = subject } }
                }.fixedSize()
            }
            DatePicker("开始时间", selection: $session.startedAt, displayedComponents: [.date, .hourAndMinute])
            DatePicker("结束时间", selection: $session.endedAt, displayedComponents: [.date, .hourAndMinute])
            HStack {
                Text("有效时长")
                Spacer()
                TextField("时", text: $hours).frame(width: 65)
                Text("时")
                TextField("分", text: $minutes).frame(width: 50)
                Text("分")
                TextField("秒", text: $seconds).frame(width: 75)
                Text("秒")
            }.textFieldStyle(.roundedBorder)
            Text("暂停不计入有效时长。调整起止时间不会自动改变有效时长。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("专注度", selection: $session.focus) {
                ForEach(["S", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存记录") { if store.upsert(candidate) { dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled(problem != nil || store.blocked)
            }
        }.padding(28).frame(width: 470)
        .onAppear {
            let value = max(0, session.activeSeconds)
            hours = String(Int(value / 3600))
            minutes = String(Int(value / 60) % 60)
            seconds = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), (value.truncatingRemainder(dividingBy: 60) * 1000).rounded(.down) / 1000)
        }.interactiveDismissDisabled()
    }
}
