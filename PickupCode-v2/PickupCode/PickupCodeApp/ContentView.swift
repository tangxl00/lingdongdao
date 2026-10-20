import SwiftUI
import OSLog

struct ContentView: View {
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        NavigationStack {
            Group {
                if let current = history.activeRecords.first {
                    activeCard(current)
                } else {
                    emptyState
                }
            }
            .navigationTitle("取件码")
            .toolbar {
                if !history.records.isEmpty {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("历史记录", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
        }
    }

    // MARK: - 当前取件码卡片

    @ViewBuilder
    private func activeCard(_ record: PickupCode) -> some View {
        let isDone = record.isCompleted || record.isExpired
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Text(record.code)
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(PickupCodeDate.isExpiringSoon(record.expiryDate) ? Color.orange : Color.accentColor)
                        .accessibilityLabel("取件码 \(record.code)")

                    Text(record.station)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    if let courier = record.courier, !courier.isEmpty {
                        Text(courier)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(record.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let note = record.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = record.code
                        } label: {
                            Label("复制取件码", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        if !isDone {
                            Button {
                                markCompleted(record)
                            } label: {
                                Label("已取件", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)

                VStack(spacing: 8) {
                    Text("灵动岛已显示")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("锁屏通知下拉即可查看，8 小时后自动消失")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                NavigationLink {
                    HistoryView()
                } label: {
                    Label("查看历史记录", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                }
            }
            .padding()
        }
    }

    // MARK: - 空态引导

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("暂无进行中的取件码")
                .font(.headline)

            Text("收到快递取件短信后，快捷指令会自动唤起本 App 并在灵动岛显示取件码")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            DisclosureGroup("什么是快捷指令？") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 打开「快捷指令」App，新建个人自动化")
                    Text("2. 选择「信息」→ 收到包含关键词（如“取件码”）的短信时触发")
                    Text("3. 添加动作「打开 URL」，填入 pickupcode://show?... 格式的链接")
                    Text("4. 详细步骤见工程内 README 与快捷指令配置指南")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))

            if !history.records.isEmpty {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("查看历史记录", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - URL 处理

    private func handleIncomingURL(_ url: URL) {
        // 灵动岛"已取件"按钮回跳：pickupcode://done?code=...
        if let doneCode = URLSchemeHandler.parseDoneCode(url) {
            history.markCompleted(code: doneCode)
            Task {
                try? await LiveActivityManager.shared.endActivity(forCode: doneCode)
            }
            return
        }

        guard let parsed = URLSchemeHandler.parse(url) else { return }

        let record = PickupCode(
            code: parsed.code,
            station: parsed.station,
            courier: parsed.courier,
            expiry: parsed.expiry,
            note: parsed.note
        )
        history.insertOrUpdate(record)

        let attributes = PickupCodeAttributes(
            code: record.code,
            station: record.station,
            courier: record.courier,
            expiry: record.expiry
        )
        let state = PickupCodeAttributes.ContentState(
            timeRemainingText: PickupCodeDate.timeRemainingText(from: record.expiryDate),
            isExpiringSoon: PickupCodeDate.isExpiringSoon(record.expiryDate),
            isCompleted: false
        )
        do {
            try LiveActivityManager.shared.startActivity(attributes: attributes, state: state)
            history.markActivityStarted(code: record.code)
        } catch {
            // 活动被系统禁用（设置里关闭 / 机型不支持）：记录仍保留，仅不显示灵动岛
            Logger(subsystem: "com.yourteam.pickupcode", category: "liveactivity")
                .error("启动灵动岛失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func markCompleted(_ record: PickupCode) {
        history.markCompleted(code: record.code)
        Task {
            try? await LiveActivityManager.shared.endActivity(forCode: record.code)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HistoryStore.shared)
}
