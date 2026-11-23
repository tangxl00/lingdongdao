import SwiftUI

/// 识别模板管理：查看内置模板、增删自定义模板、编辑正则与样例。
struct TemplatesView: View {
    @EnvironmentObject private var store: FloatyStore
    @Environment(\.dismiss) private var dismiss

    @State private var editing: RecognitionTemplate?
    @State private var showNew = false

    var body: some View {
        List {
            Section {
                ForEach(FloatyKind.allCases) { kind in
                    let group = store.templates.filter { $0.kind == kind }
                    if !group.isEmpty {
                        ForEach(group) { template in
                            Button {
                                editing = template
                            } label: {
                                TemplateRow(template: template)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("模板")
            } footer: {
                Text("模板使用命名捕获组：code / place / train / flight / from / to / departure / arrival / departureTerminal / arrivalTerminal / seat / car / gate / headline / note")
            }

            Section {
                Button {
                    showNew = true
                } label: {
                    Label("新建模板", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("识别模板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .sheet(item: $editing) { template in
            NavigationStack {
                TemplateEditorView(template: template)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                TemplateEditorView(template: RecognitionTemplate(
                    kind: .pickup,
                    name: "新模板",
                    regex: #"取件码[:：]?\s*(?<code>[A-Za-z0-9\-]+)"#,
                    isBuiltin: false,
                    sample: "取件码：886677"
                ))
                .environmentObject(store)
            }
        }
    }
}

/// 模板行
struct TemplateRow: View {
    let template: RecognitionTemplate

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: template.kind.symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.body)
                    if template.isBuiltin {
                        Text("内置")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(template.regex)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// 模板编辑：名称 / 类型 / 正则 / 样例 + 实时测试。
struct TemplateEditorView: View {
    @EnvironmentObject private var store: FloatyStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecognitionTemplate
    @State private var testText: String = ""
    @State private var testResult: String = ""

    init(template: RecognitionTemplate) {
        _draft = State(initialValue: template)
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $draft.name)
                Picker("类型", selection: $draft.kind) {
                    ForEach(FloatyKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                    }
                }
            }

            Section {
                TextField("正则表达式", text: $draft.regex, axis: .vertical)
                    .font(.caption.monospaced())
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !draft.regex.isEmpty && draft.compiled() == nil {
                    Label("正则无法编译，请检查语法", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("正则")
            } footer: {
                Text("示例：取件码 (?<code>...)、车次 (?<train>...)、航班 (?<flight>...)、出发 (?<departure>...)、起点 (?<from>...)、终点 (?<to>...)、座位 (?<seat>...)、车厢 (?<car>...)、检票口 (?<gate>...)、航站楼 (?<departureTerminal>...)、标题 (?<headline>...)、备注 (?<note>...)")
            }

            Section("样例") {
                TextField("样例文本", text: $draft.sample, axis: .vertical)
                    .lineLimit(1...4)
                if !draft.sample.isEmpty {
                    Button("用样例测试") {
                        testText = draft.sample
                        runTest()
                    }
                }
            }

            Section("测试") {
                TextField("粘贴一段短信 / 邮件内容", text: $testText, axis: .vertical)
                    .lineLimit(3...8)
                Button("测试识别") { runTest() }
                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    store.addTemplate(draft)
                    dismiss()
                } label: {
                    Label("保存", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.compiled() == nil)

                if !draft.isBuiltin {
                    Button(role: .destructive) {
                        store.deleteTemplate(id: draft.id)
                        dismiss()
                    } label: {
                        Label("删除模板", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(draft.isBuiltin ? "编辑内置模板" : "编辑模板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("取消") { dismiss() }
            }
        }
    }

    private func runTest() {
        let result = RecognitionEngine.recognize(text: testText,
                                                templates: [draft],
                                                builtinPickupEnabled: true)
        if let result {
            testResult = "命中「\(result.templateName)」：\(result.item.kind.displayName) · 标题 \(result.item.title)"
                + (result.item.displaySubtitle.map { " · \($0)" } ?? "")
        } else {
            testResult = "未命中该模板"
        }
    }
}

#Preview {
    NavigationStack {
        TemplatesView()
            .environmentObject(FloatyStore.shared)
    }
}
