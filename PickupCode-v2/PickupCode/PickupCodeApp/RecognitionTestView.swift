import SwiftUI

/// 识别测试：粘贴文本 → 看命中哪个模板、解析出哪些字段。
struct RecognitionTestView: View {
    @EnvironmentObject private var store: FloatyStore

    @State private var text: String = ""
    @State private var results: [RecognitionEngine.Result] = []

    var body: some View {
        Form {
            Section {
                TextField("粘贴短信 / 邮件内容", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    run()
                } label: {
                    Label("识别", systemImage: "wand.and.rays")
                        .frame(maxWidth: .infinity)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !results.isEmpty {
                    Button {
                        addAll()
                    } label: {
                        Label("全部添加到「此刻」", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Section("内置样例") {
                ForEach(BuiltinTemplates.all) { template in
                    Button {
                        text = template.sample
                        run()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.subheadline.weight(.semibold))
                            Text(template.sample)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !results.isEmpty {
                Section("识别结果") {
                    ForEach(results, id: \.item.id) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(result.templateName, systemImage: result.item.kind.symbolName)
                                .font(.subheadline.weight(.semibold))
                            Text(result.item.title)
                                .font(.body.monospaced())
                            if let subtitle = result.item.displaySubtitle {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            if let detail = result.item.detailText {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("测试识别")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() {
        results = RecognitionEngine.recognizeList(texts: [text],
                                                 templates: store.templates,
                                                 builtinPickupEnabled: store.settings.builtinPickupEnabled)
    }

    private func addAll() {
        for result in results {
            store.insertOrUpdate(result.item)
        }
        AutoAddEngine.refreshBoard()
        results = []
    }
}

#Preview {
    NavigationStack {
        RecognitionTestView()
            .environmentObject(FloatyStore.shared)
    }
}
