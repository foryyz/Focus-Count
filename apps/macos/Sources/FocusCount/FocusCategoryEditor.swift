import SwiftUI

struct FocusCategoryEditor: View {
    @ObservedObject var appearance: FocusAppearanceStore
    let activities: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var search = ""
    @State private var removing: FocusCategory?
    @State private var renaming: FocusCategory?
    @State private var renameText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("分类与颜色").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("每个活动归入一个分类，设置应用于该活动的所有历史记录。删除分类会将活动移回未分类，不删除记录。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("新分类，例如学习、娱乐", text: $newName).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("创建分类", action: add).disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appearance.settings.categories) { category in
                        HStack {
                            ColorPicker(category.name, selection: Binding(get: { appearance.color("category:" + category.id.uuidString) }, set: { appearance.setColor($0, key: "category:" + category.id.uuidString) }), supportsOpacity: false)
                            Spacer()
                            Text("\(activities.filter { appearance.categoryID($0) == category.id }.count) 个活动").foregroundStyle(.secondary)
                            Button("重命名") { renameText = category.name; renaming = category }
                            Button { removing = category } label: { Image(systemName: "trash") }.help("删除分类，保留活动记录")
                        }
                    }
                    if appearance.settings.categories.isEmpty { Text("尚无分类，可创建“学习”“工作”“娱乐”等集合。").foregroundStyle(.secondary) }
                }.padding(4)
            }.frame(maxHeight: 160)
            Divider()
            TextField("搜索活动", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(activities.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { activity in
                        HStack {
                            ColorPicker(activity, selection: Binding(get: { appearance.color("activity:" + activity) }, set: { appearance.setColor($0, key: "activity:" + activity) }), supportsOpacity: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Picker("分类", selection: Binding(get: { appearance.categoryID(activity)?.uuidString ?? "" }, set: { appearance.assign(activity, to: UUID(uuidString: $0)) })) {
                                Text("未分类").tag("")
                                ForEach(appearance.settings.categories) { Text($0.name).tag($0.id.uuidString) }
                            }.labelsHidden().frame(width: 180).accessibilityLabel("\(activity)的分类")
                        }
                        Divider()
                    }
                    if activities.isEmpty { Text("保存或补记专注记录后，可在这里为活动分配分类和颜色。").foregroundStyle(.secondary) }
                }.padding(4)
            }
            if let error = appearance.error { Text(error).foregroundStyle(.red).font(.caption) }
            Text("分类与颜色保存在本机，暂不随 JSON 同步；活动名称修改后视为新活动，需重新分配分类。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 640, height: 620)
            .alert("删除“\(removing?.name ?? "")”？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("取消", role: .cancel) { removing = nil }
                Button("删除分类", role: .destructive) { if let removing { appearance.remove(removing.id) }; removing = nil }
            } message: { Text("所属活动将移回未分类，所有专注记录仍保留。") }
            .alert("重命名分类", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("分类名称", text: $renameText)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") { if let renaming { appearance.rename(renaming.id, to: renameText) }; renaming = nil }
            }
            .onChange(of: appearance.settings.categories) { _ in appearance.ensureColors(activities) }
    }
    private func add() { guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; if appearance.addCategory(newName) { newName = "" } }
}
