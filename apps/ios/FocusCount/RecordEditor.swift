import SwiftUI
import FocusCountCore

struct RecordEditor: View {
    @ObservedObject var store: PhoneStore
    @State var session: StudySession
    var completesTimer = false
    var onSave: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var hours = ""
    @State private var minutes = ""
    @State private var seconds = ""
    private var total: Double? {
        guard let h = Double(hours), let m = Double(minutes), let s = Double(seconds.replacingOccurrences(of: ",", with: ".")), h.isFinite, m.isFinite, s.isFinite,
              h >= 0, h.rounded() == h, m >= 0, m < 60, m.rounded() == m, s >= 0, s < 60 else { return nil }
        return h * 3600 + m * 60 + s
    }
    private var candidate: StudySession {
        var value = session; value.activeSeconds = completesTimer ? session.activeSeconds : total ?? -1; return value
    }
    private var issue: String? { candidate.validationError }
    var body: some View {
        NavigationStack {
            Form {
                Section("学习内容") {
                    TextField("学习科目", text: $session.subject)
                    if !store.subjects.isEmpty {
                        Menu("选择已有科目") { ForEach(store.subjects, id: \.self) { name in Button(name) { session.subject = name } } }
                    }
                }
                Section {
                    Picker("专注度", selection: $session.focus) {
                        ForEach(["S", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                } header: { Text("专注度") } footer: { Text("S 最高 · D 最低，按这次学习的感受选择。") }
                Section {
                    if completesTimer {
                        LabeledContent("有效学习时间", value: phoneDuration(session.activeSeconds))
                    } else {
                        DatePicker("开始", selection: $session.startedAt)
                        DatePicker("结束", selection: $session.endedAt)
                        HStack {
                            Text("有效时长"); Spacer()
                            TextField("时", text: $hours).frame(width: 40).keyboardType(.numberPad)
                            Text("时").foregroundStyle(.secondary)
                            TextField("分", text: $minutes).frame(width: 35).keyboardType(.numberPad)
                            Text("分").foregroundStyle(.secondary)
                            TextField("秒", text: $seconds).frame(width: 55).keyboardType(.decimalPad)
                            Text("秒").foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("时间") } footer: { Text("暂停不计入有效时长，修改起止时间不会自动改变有效时长。") }
                if let issue { Section { Text(issue).font(.footnote).foregroundStyle(.orange) } }
                if let error = store.error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle(completesTimer ? "完成本次学习" : "学习记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(completesTimer ? "返回计时" : "取消") {
                        if completesTimer { store.returnToTimer() } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { if store.save(candidate, completesTimer: completesTimer) { onSave(); dismiss() } }
                        .fontWeight(.semibold).disabled(issue != nil || store.blocked)
                }
            }
            .onAppear {
                let value = max(0, session.activeSeconds)
                hours = String(Int(value / 3600)); minutes = String(Int(value / 60) % 60)
                seconds = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), (value.truncatingRemainder(dividingBy: 60) * 1000).rounded(.down) / 1000)
            }
        }.interactiveDismissDisabled()
    }
}
