import SwiftUI
import UIKit

/// 设置：锁屏显示 / 自动添加 / 看板过滤 / 模板 / 外观 / 关于。
struct SettingsView: View {
    @EnvironmentObject private var store: FloatyStore
    @State private var showTemplates = false

    var body: some View {
        Form {
            // MARK: - 锁屏显示

            Section("锁屏显示") {
                Toggle("在锁屏显示看板", isOn: binding(\.showOnLockScreen))
                    .onChange(of: store.settings.showOnLockScreen) { _, newValue in
                        if newValue {
                            AutoAddEngine.refreshBoard()
                        } else {
                            Task { await BoardActivityManager.shared.dismissAll() }
                        }
                    }
                Toggle("显示时间", isOn: binding(\.showTime))
                Toggle("紧凑视图", isOn: binding(\.compactView))
                Toggle("最小化显示", isOn: binding(\.minimizeDisplay))
                if store.settings.minimizeDisplay {
                    Toggle("最小化时隐藏内容", isOn: binding(\.hideContentWhenMinimized))
                }
                Toggle("显示详情", isOn: binding(\.showDetails))
                Toggle("同地点内排序", isOn: binding(\.sortWithinLocation))
                Toggle("卡片上显示完成按钮", isOn: binding(\.showCompleteButton))
            }

            // MARK: - 看板过滤

            Section("看板内容") {
                Picker("类型", selection: binding(\.boardFilter)) {
                    ForEach(BoardKindFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                if store.settings.boardFilter != .off {
                    ForEach(FloatyKind.allCases) { kind in
                        Toggle(kind.displayName, isOn: bindingForKind(kind))
                    }
                }
                Stepper(value: binding(\.itemsPerPage), in: 1...6) {
                    HStack {
                        Text("每页卡片数")
                        Spacer()
                        Text("\(store.settings.itemsPerPage)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - 自动添加

            Section {
                Toggle("内置取件识别", isOn: binding(\.builtinPickupEnabled))
                Toggle("打开时扫描剪贴板", isOn: binding(\.scanClipboardOnOpen))
                Toggle("每日取件提醒", isOn: binding(\.dailyReminder))
                    .onChange(of: store.settings.dailyReminder) { _, newValue in
                        ReminderScheduler.scheduleDailyReminder(enabled: newValue,
                                                              time: store.settings.dailyReminderTime)
                    }
                if store.settings.dailyReminder {
                    DatePicker("提醒时间", selection: dailyReminderBinding, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("自动添加")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自动添加在本工程中永久免费可用（\(ProAccess.proDescription)）。")
                    Text("按《快捷指令配置指南》创建短信 / 邮件自动化后，符合模板的文本会自动出现在「此刻」。")
                }
            }

            // MARK: - 识别模板

            Section("识别模板") {
                Button {
                    showTemplates = true
                } label: {
                    HStack {
                        Label("管理识别模板", systemImage: "text.magnifyingglass")
                        Spacer()
                        Text("\(store.templates.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    RecognitionTestView()
                } label: {
                    Label("测试识别", systemImage: "wand.and.rays")
                }
            }

            // MARK: - 外观

            Section("外观") {
                Picker("主题", selection: binding(\.appearance)) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                Picker("语言", selection: binding(\.language)) {
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
            }

            // MARK: - 数据

            Section("数据") {
                Button(role: .destructive) {
                    store.clearCompleted()
                } label: {
                    Label("清除已完成内容", systemImage: "trash")
                }
                Button(role: .destructive) {
                    store.clearAll()
                } label: {
                    Label("清空全部内容", systemImage: "trash.fill")
                }
            }

            // MARK: - 关于

            Section("关于") {
                LabeledContent("版本", value: "1.1.0")
                LabeledContent("版本性质", value: ProAccess.proDescription)
                VStack(alignment: .leading, spacing: 4) {
                    Text("隐私")
                        .font(.subheadline.weight(.semibold))
                    Text("全部识别在本机完成，文本不上传、不联网、无云端 AI。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTemplates) {
            NavigationStack {
                TemplatesView()
                    .environmentObject(store)
            }
        }
    }

    // MARK: - 绑定

    private func binding(_ keyPath: WritableKeyPath<FloatySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<FloatySettings, Int>) -> Binding<Int> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<FloatySettings, String>) -> Binding<String> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<FloatySettings, BoardKindFilter>) -> Binding<BoardKindFilter> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func bindingForKind(_ kind: FloatyKind) -> Binding<Bool> {
        Binding(
            get: { store.settings.boardKinds.contains(kind) },
            set: { isOn in
                store.updateSettings { settings in
                    if isOn {
                        _ = settings.boardKinds.insert(kind)
                    } else {
                        _ = settings.boardKinds.remove(kind)
                    }
                }
            }
        )
    }

    /// 每日提醒时间（HH:mm 字符串 ↔ Date）
    private var dailyReminderBinding: Binding<Date> {
        Binding(
            get: { FloatyDate.parseTimeOnly(store.settings.dailyReminderTime) ?? Date() },
            set: { newValue in
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                let text = formatter.string(from: newValue)
                store.updateSettings { $0.dailyReminderTime = text }
                ReminderScheduler.scheduleDailyReminder(enabled: store.settings.dailyReminder, time: text)
            }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(FloatyStore.shared)
    }
}
