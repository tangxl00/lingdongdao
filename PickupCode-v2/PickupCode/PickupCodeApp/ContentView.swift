import SwiftUI
import OSLog

/// 主界面：「此刻」列表 —— 取件码 / 火车票 / 机票 / 待办 全部内容。
struct ContentView: View {
    @EnvironmentObject private var store: FloatyStore
    @Environment(\.scenePhase) private var scenePhase

    /// 快捷指令请求打开的添加类型
    @State private var pendingComposeKind: FloatyKind?

    var body: some View {
        NavigationStack {
            Group {
                if store.activeItems.isEmpty {
                    emptyState
                } else {
                    nowList
                }
            }
            .navigationTitle("此刻")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        NavigationLink {
                            AddItemView()
                        } label: {
                            Label("添加", systemImage: "plus")
                        }
                        NavigationLink {
                            HistoryView()
                        } label: {
                            Label("历史记录", systemImage: "clock.arrow.circlepath")
                        }
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AddItemView()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onAppear {
                // 快捷指令请求的添加类型（ComposeAttentionIntent 等）
                if let kind = FloatyRepository.takePendingComposeKind() {
                    pendingComposeKind = kind
                }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                if let kind = FloatyRepository.takePendingComposeKind() {
                    pendingComposeKind = kind
                }
            }
            .sheet(item: $pendingComposeKind) { kind in
                NavigationStack {
                    AddItemView(kind: kind)
                        .environmentObject(store)
                }
            }
        }
    }

    // MARK: - 此刻列表

    private var nowList: some View {
        List {
            if store.settings.showOnLockScreen {
                Section {
                    BoardSummaryRow()
                }
            }

            ForEach(FloatyKind.allCases) { kind in
                let kindItems = store.activeItems.filter { $0.kind == kind }
                if !kindItems.isEmpty {
                    Section(kind.displayName) {
                        ForEach(kindItems) { item in
                            ItemRow(item: item)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 空态引导

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("此刻没有内容")
                .font(.headline)

            Text("添加取件码、火车票、机票或待办，或让短信与邮件自动添加")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                NavigationLink {
                    AddItemView()
                } label: {
                    Label("手动添加", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("设置自动添加", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
            }

            DisclosureGroup("什么是自动添加？") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 在「设置 → 识别模板」里确认模板")
                    Text("2. 按《快捷指令配置指南》创建短信 / 邮件自动化")
                    Text("3. 符合模板的短信与邮件会自动出现在这里")
                    Text("全部在本机匹配，文本不离开你的设备")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding()
    }

    // MARK: - URL 处理

    private func handleIncomingURL(_ url: URL) {
        // 完成回跳：floaty://done?id=... （或旧契约 code=）
        if let id = FloatyURL.parseDoneID(url) {
            store.markCompleted(id: id)
            AutoAddEngine.refreshBoard()
            return
        }
        if let code = FloatyURL.parseDoneCode(url) {
            store.markCompleted(code: code)
            AutoAddEngine.refreshBoard()
            return
        }

        // 自动添加入口：floaty://add?text=...&source=sms
        if url.host?.lowercased() == "add",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let text = components.queryItems?.first(where: { $0.name == "text" })?.value {
            let sourceRaw = components.queryItems?.first(where: { $0.name == "source" })?.value ?? "sms"
            let source = AutoAddEngine.Source(rawValue: sourceRaw.lowercased()) ?? .sms
            if let item = AutoAddEngine.add(text: text, source: source) {
                if item.kind == .todo {
                    ReminderScheduler.scheduleDeadlineReminder(for: item)
                }
            }
            return
        }

        // 展示入口：floaty://show?...
        guard let parsed = FloatyURL.parse(url) else { return }

        let item = FloatyItem(
            kind: parsed.kind,
            title: parsed.title,
            subtitle: parsed.subtitle,
            detail: parsed.detail,
            from: parsed.from,
            to: parsed.to,
            departure: parsed.departure,
            arrival: parsed.arrival,
            due: parsed.due,
            seat: parsed.seat,
            car: parsed.car,
            gate: parsed.gate,
            terminal: parsed.terminal,
            note: parsed.note
        )
        store.insertOrUpdate(item)
        if item.kind == .todo {
            ReminderScheduler.scheduleDeadlineReminder(for: item)
        }
        AutoAddEngine.refreshBoard()
    }
}

/// 单条内容的行视图
struct ItemRow: View {
    @EnvironmentObject private var store: FloatyStore
    let item: FloatyItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: item.kind.symbolName)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                Text(item.title)
                    .font(.title3.weight(.bold).monospaced())
                    .lineLimit(1)

                Spacer()

                if item.checklistTotal > 0 {
                    Text("\(item.checklistDone)/\(item.checklistTotal)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let subtitle = item.displaySubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let detail = item.detailText {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(FloatyDate.timeRemainingText(from: item.referenceDate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FloatyDate.isExpiringSoon(item.referenceDate) ? .orange : .secondary)

                if let due = item.dueDate {
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.deleteRecord(id: item.id)
            } label: {
                Label("删除", systemImage: "trash")
            }

            Button {
                store.markCompleted(id: item.id)
                AutoAddEngine.refreshBoard()
            } label: {
                Label("完成", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
    }
}

/// 锁屏看板状态摘要行
struct BoardSummaryRow: View {
    @EnvironmentObject private var store: FloatyStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.rectangle")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("锁屏看板")
                    .font(.subheadline.weight(.semibold))
                Text("第 \(store.boardPageIndex + 1) / \(max(1, store.boardPageCount)) 页 · \(store.boardItems.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.boardPageCount > 1 {
                Button {
                    store.setPageIndex(store.boardPageIndex - 1)
                    AutoAddEngine.refreshBoard()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(store.boardPageIndex <= 0)

                Button {
                    store.setPageIndex(store.boardPageIndex + 1)
                    AutoAddEngine.refreshBoard()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(store.boardPageIndex >= store.boardPageCount - 1)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(FloatyStore.shared)
}
