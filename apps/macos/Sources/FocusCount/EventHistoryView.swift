import SwiftUI
import FocusCountCore

struct EventHistoryView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleted = false
    @State private var deleting: TimeEvent?
    @State private var purging: TimeEvent?
    private var events: [TimeEvent] {
        (store.database.events ?? []).filter { ($0.deletedAt != nil) == deleted }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button("返回记录") { dismiss() }.keyboardShortcut(.cancelAction)
                Text("时间标记").font(.title2.bold())
                Spacer()
                Text("\(events.count) 次").foregroundStyle(.secondary)
            }
            Picker("范围", selection: $deleted) {
                Text("时间标记").tag(false)
                Text("最近删除").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            Text("输入 !sex 并回车，记录一次 SEX 及当下时间；不计时，也不影响正在进行的专注。")
                .font(.caption).foregroundStyle(.secondary)
            if events.isEmpty {
                Text(deleted ? "没有已删除的时间标记" : "暂无时间标记")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(events) { event in
                    HStack {
                        Image(systemName: "mappin.circle").foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.kind).font(.headline)
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if deleted {
                            Button("恢复") { store.setEventDeleted(event.id, deleted: false) }
                            Button("彻底删除", role: .destructive) { purging = event }
                        } else {
                            Button("删除", role: .destructive) { deleting = event }
                        }
                    }.padding(.vertical, 5).disabled(store.blocked)
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
        }.padding(24).frame(width: 650, height: 520)
        .alert("删除这次时间标记？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("移至最近删除", role: .destructive) {
                if let deleting { store.setEventDeleted(deleting.id, deleted: true) }
                deleting = nil
            }
        }
        .alert("彻底删除这次时间标记？", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } })) {
            Button("取消", role: .cancel) { purging = nil }
            Button("彻底删除", role: .destructive) {
                if let purging { store.purgeEvents([purging.id]) }
                purging = nil
            }
        } message: { Text("无法在应用内恢复，旧文件导入也不会重新出现。已有独立备份不受影响。") }
    }
}
