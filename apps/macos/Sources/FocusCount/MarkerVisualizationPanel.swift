import SwiftUI
import FocusCountCore

struct MarkerVisualizationPanel: View {
    let events: [TimeEvent]
    let start: Date
    let end: Date
    @ObservedObject var colors: MarkerColors
    let isWeek: Bool
    let edit: (TimeEvent) -> Void
    let delete: (TimeEvent) -> Void
    @State private var mode = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("显示方式", selection: $mode) {
                Text("频率总览").tag(0)
                Text("折线趋势").tag(1)
                Text("时间分布").tag(2)
            }.pickerStyle(.segmented).frame(width: 290)
            if mode == 0 {
                MarkerFrequencyOverview(events: events, start: start, end: isWeek ? Calendar.current.date(byAdding: .day, value: 7, to: start)! : end, isWeek: isWeek, colors: colors, edit: edit, delete: delete)
                    .padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            } else {
                MarkerTimelineChart(events: events, start: start, end: end, colors: colors, isWeek: isWeek, line: mode == 1)
                    .id(mode)
            }
        }
    }
}

struct MarkerEventEditor: View {
    let event: TimeEvent
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var date: Date
    @State private var failed = false
    init(event: TimeEvent, store: StudyStore) {
        self.event = event; self.store = store
        _name = State(initialValue: event.kind); _date = State(initialValue: event.occurredAt)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑时间标记").font(.headline)
            TextField("标记内容", text: $name).textFieldStyle(.roundedBorder)
            DatePicker("时间", selection: $date, in: ...Date())
            if failed { Text(store.error ?? "无法保存；记录可能已被删除。").font(.caption).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    if store.updateEvent(event.id, kind: name, at: date) { dismiss() } else { failed = true }
                }.keyboardShortcut(.defaultAction).disabled(store.blocked || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 360)
    }
}
