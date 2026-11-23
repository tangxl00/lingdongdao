import AppIntents
import Foundation

// MARK: - 枚举（对应 Floaty 的 ComposeKind / BoardKindFilter）

/// 内容类型（对应 Floaty 的 `floaty.ComposeKind`）
enum ComposeKind: String, AppEnum, CaseIterable {
    case pickup
    case todo
    case train
    case flight

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "内容类型"

    static var caseDisplayRepresentations: [ComposeKind: DisplayRepresentation] = [
        .pickup: "取件码",
        .todo: "待办",
        .train: "火车票",
        .flight: "机票"
    ]

    var floatyKind: FloatyKind {
        switch self {
        case .pickup: return .pickup
        case .todo: return .todo
        case .train: return .train
        case .flight: return .flight
        }
    }

    /// 中文名称
    var displayName: String {
        switch self {
        case .pickup: return "取件码"
        case .todo: return "待办"
        case .train: return "火车票"
        case .flight: return "机票"
        }
    }
}

/// 看板类型过滤方式（对应 Floaty 的 `floaty.BoardKindFilter`）
enum BoardFilterOption: String, AppEnum, CaseIterable {
    case off
    case only
    case except

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "过滤方式"

    static var caseDisplayRepresentations: [BoardFilterOption: DisplayRepresentation] = [
        .off: "不显示",
        .only: "仅显示所选类型",
        .except: "排除所选类型"
    ]

    var filter: BoardKindFilter {
        switch self {
        case .off: return .off
        case .only: return .only
        case .except: return .except
        }
    }
}

/// 锁屏看板显示模式（对应 Floaty `ComposeControlIntent` 的开关语义）
enum BoardDisplayMode: String, AppEnum, CaseIterable {
    case toggle
    case show
    case hide

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "显示模式"

    static var caseDisplayRepresentations: [BoardDisplayMode: DisplayRepresentation] = [
        .toggle: "切换显示",
        .show: "显示",
        .hide: "隐藏"
    ]
}

// MARK: - 共享逻辑

/// Intent 与主 App 共用的数据操作（不依赖 UI 线程状态）。
enum IntentSupport {

    /// 当前设置
    static func settings() -> FloatySettings {
        FloatyRepository.loadSettings()
    }

    /// 写入设置
    static func saveSettings(_ settings: FloatySettings) {
        FloatyRepository.saveSettings(settings)
    }

    /// 内容列表
    static func items() -> [FloatyItem] {
        FloatyRepository.loadItems()
    }

    /// 写入内容列表
    static func saveItems(_ items: [FloatyItem]) {
        FloatyRepository.saveItems(items)
    }

    /// 插入或更新一条内容
    static func upsert(_ item: FloatyItem) {
        var list = items()
        list = FloatyRepository.upsert(item, into: list)
        saveItems(list)
    }

    /// 标记完成
    static func markCompleted(id: UUID) {
        var list = items()
        list = FloatyRepository.markCompleted(id: id, in: list)
        saveItems(list)
    }

    /// 勾选 / 取消勾选待办子项
    static func toggleChecklist(itemID: UUID, lineID: UUID) {
        var list = items()
        list = FloatyRepository.toggleChecklist(itemID: itemID, lineID: lineID, in: list)
        saveItems(list)
    }

    /// 当前聚焦的看板内容
    static func focusedItem() -> FloatyItem? {
        let settings = self.settings()
        let board = FloatyBoard.visibleItems(from: items(), settings: settings)
        let page = FloatyBoard.page(board, index: FloatyBoard.pageIndex(), perPage: max(1, settings.itemsPerPage))
        let index = min(max(0, FloatyBoard.focusIndex()), max(0, page.count - 1))
        return page.isEmpty ? nil : page[index]
    }

    /// 刷新 / 启动锁屏看板
    static func presentBoard() {
        let store = FloatyStore.shared
        BoardActivityManager.shared.present(items: store.items,
                                            settings: store.settings,
                                            pageIndex: store.boardPageIndex,
                                            focusIndex: store.boardFocusIndex)
    }

    /// 计算新的聚焦下标
    static func nextFocusIndex(delta: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let current = FloatyBoard.focusIndex()
        return min(max(0, current + delta), pageCount - 1)
    }

    /// 计算新的页码
    static func nextPageIndex(delta: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let current = FloatyBoard.pageIndex()
        return min(max(0, current + delta), pageCount - 1)
    }

    /// 解析类型列表字符串（逗号 / 空格 / 换行分隔，也接受中文名）。
    /// 空字符串表示「全部类型」。
    static func kinds(fromText text: String) -> Set<FloatyKind> {
        let separators = CharacterSet(charactersIn: ",，;； \t\n")
        let parts = text.components(separatedBy: separators)
        var result = Set<FloatyKind>()
        for part in parts {
            let key = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            switch key {
            case "pickup", "取件码", "取件":
                result.insert(.pickup)
            case "todo", "待办":
                result.insert(.todo)
            case "train", "火车票", "火车":
                result.insert(.train)
            case "flight", "机票", "航班":
                result.insert(.flight)
            default:
                if let kind = FloatyKind(rawValue: key) {
                    result.insert(kind)
                }
            }
        }
        return result
    }

    /// 解析多段文本（按换行分隔，`---` 也视作分隔符）。
    static func texts(fromBlock block: String) -> [String] {
        var result: [String] = []
        for raw in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line == "---" { continue }
            result.append(line)
        }
        return result
    }
}

// MARK: - 组合：添加内容

/// 打开 App 并添加指定类型的内容（对应 `ComposeAttentionIntent`）。
struct ComposeAttentionIntent: AppIntent {
    static var title: LocalizedStringResource = "添加内容"
    static var description: IntentDescription? = IntentDescription("打开 App 添加取件码、待办、火车票或机票")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "类型", default: ComposeKind.pickup)
    var kind: ComposeKind

    func perform() async throws -> some IntentResult & ProvidesDialog {
        FloatyRepository.savePendingComposeKind(kind.floatyKind)
        return .result(dialog: "打开 App 添加\(kind.displayName)")
    }
}

/// 添加取件码（快捷指令）
struct AddPickupCodeIntent: AppIntent {
    static var title: LocalizedStringResource = "添加取件码"
    static var description: IntentDescription? = IntentDescription("打开 App 添加取件码")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        FloatyRepository.savePendingComposeKind(.pickup)
        return .result(dialog: "打开 App 添加取件码")
    }
}

/// 添加待办（快捷指令）
struct AddTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "添加待办"
    static var description: IntentDescription? = IntentDescription("打开 App 添加待办")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        FloatyRepository.savePendingComposeKind(.todo)
        return .result(dialog: "打开 App 添加待办")
    }
}

/// 添加火车票（快捷指令）
struct AddTrainTicketIntent: AppIntent {
    static var title: LocalizedStringResource = "添加火车票"
    static var description: IntentDescription? = IntentDescription("打开 App 添加火车票")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        FloatyRepository.savePendingComposeKind(.train)
        return .result(dialog: "打开 App 添加火车票")
    }
}

/// 添加机票（快捷指令）
struct AddFlightTicketIntent: AppIntent {
    static var title: LocalizedStringResource = "添加机票"
    static var description: IntentDescription? = IntentDescription("打开 App 添加机票")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        FloatyRepository.savePendingComposeKind(.flight)
        return .result(dialog: "打开 App 添加机票")
    }
}

/// 打开添加页（对应 `ComposePickerIntent`）
struct ComposePickerIntent: AppIntent {
    static var title: LocalizedStringResource = "打开添加页"
    static var description: IntentDescription? = IntentDescription("打开 App 的添加页面")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        FloatyRepository.savePendingComposeKind(.pickup)
        return .result(dialog: "打开添加页")
    }
}

/// 控制中心 / 快捷指令：开关锁屏看板（对应 `ComposeControlIntent`）
struct ComposeControlIntent: AppIntent {
    static var title: LocalizedStringResource = "切换锁屏看板"
    static var description: IntentDescription? = IntentDescription("开启或关闭锁屏看板显示")
    static var openAppWhenRun: Bool = false

    /// 默认「切换」：按当前状态取反
    @Parameter(title: "模式", default: BoardDisplayMode.toggle)
    var mode: BoardDisplayMode

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var settings = IntentSupport.settings()
        let target: Bool
        switch mode {
        case .toggle: target = !settings.showOnLockScreen
        case .show: target = true
        case .hide: target = false
        }
        settings.showOnLockScreen = target
        if target && settings.boardFilter == .off {
            settings.boardFilter = .only
            settings.boardKinds = Set(FloatyKind.allCases)
        }
        IntentSupport.saveSettings(settings)

        if target {
            IntentSupport.presentBoard()
            FloatyBoard.setVisible(true)
            return .result(dialog: "已显示锁屏看板")
        } else {
            await BoardActivityManager.shared.dismissAll()
            FloatyBoard.setVisible(false)
            return .result(dialog: "已隐藏锁屏看板")
        }
    }
}

// MARK: - 识别

/// 识别文本（对应 `RecognizeTextIntent`）
struct RecognizeTextIntent: AppIntent {
    static var title: LocalizedStringResource = "识别文本"
    static var description: IntentDescription? = IntentDescription("从短信、邮件或通知文本中识别取件码、火车票、机票或待办")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "文本", default: "")
    var text: String
    @Parameter(title: "快捷指令 ID", default: "")
    var shortcutID: String
    @Parameter(title: "快捷指令版本", default: "")
    var shortcutVersion: String
    @Parameter(title: "模式", default: "")
    var mode: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = IntentSupport.settings()
        let result = RecognitionEngine.recognize(text: text,
                                                 templates: FloatyRepository.loadTemplates(),
                                                 builtinPickupEnabled: settings.builtinPickupEnabled)
        guard let result else {
            return .result(dialog: "未识别到内容")
        }
        IntentSupport.upsert(result.item)
        if result.item.kind == .todo {
            ReminderScheduler.scheduleDeadlineReminder(for: result.item)
        }
        return .result(dialog: "已添加 \(result.item.title)")
    }
}

/// 识别多段文本（对应 `RecognizeTextListIntent`）
///
/// 说明：AppIntents 不支持 `[String]` 集合参数，这里用「多行文本」承载批量输入，
/// 每行一段（`---` 视为空行忽略）。
struct RecognizeTextListIntent: AppIntent {
    static var title: LocalizedStringResource = "识别文本列表"
    static var description: IntentDescription? = IntentDescription("批量识别文本并添加到「此刻」")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "文本列表", default: "")
    var texts: String
    @Parameter(title: "快捷指令 ID", default: "")
    var shortcutID: String
    @Parameter(title: "快捷指令版本", default: "")
    var shortcutVersion: String
    @Parameter(title: "模式", default: "")
    var mode: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = IntentSupport.settings()
        let blocks = IntentSupport.texts(fromBlock: texts)
        let results = RecognitionEngine.recognizeList(texts: blocks,
                                                      templates: FloatyRepository.loadTemplates(),
                                                      builtinPickupEnabled: settings.builtinPickupEnabled)
        for result in results {
            IntentSupport.upsert(result.item)
            if result.item.kind == .todo {
                ReminderScheduler.scheduleDeadlineReminder(for: result.item)
            }
        }
        if results.isEmpty {
            return .result(dialog: "未识别到内容")
        }
        return .result(dialog: "已添加 \(results.count) 条内容")
    }
}

// MARK: - 锁屏看板控制

/// 在锁屏显示看板（对应 `ShowLockScreenBoardIntent`）
///
/// 说明：AppIntents 不支持 `[ComposeKind]` 集合参数，这里用逗号分隔的类型串，
/// 留空表示全部类型（如 `pickup,todo`）。
struct ShowLockScreenBoardIntent: AppIntent {
    static var title: LocalizedStringResource = "在锁屏显示"
    static var description: IntentDescription? = IntentDescription("在锁屏显示「此刻」看板")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "类型", default: "")
    var kinds: String
    @Parameter(title: "过滤方式", default: BoardFilterOption.only)
    var filter: BoardFilterOption

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var settings = IntentSupport.settings()
        settings.showOnLockScreen = true
        settings.boardFilter = filter.filter
        let selected = IntentSupport.kinds(fromText: kinds)
        if !selected.isEmpty {
            settings.boardKinds = selected
        } else if settings.boardKinds.isEmpty {
            settings.boardKinds = Set(FloatyKind.allCases)
        }
        IntentSupport.saveSettings(settings)

        IntentSupport.presentBoard()
        FloatyBoard.setVisible(true)
        return .result(dialog: "已在锁屏显示看板")
    }
}

/// 在锁屏隐藏看板（对应 `HideLockScreenBoardIntent`）
struct HideLockScreenBoardIntent: AppIntent {
    static var title: LocalizedStringResource = "不在锁屏显示"
    static var description: IntentDescription? = IntentDescription("隐藏锁屏看板")
    static var openAppWhenRun: Bool = false

    /// 留空表示隐藏全部类型
    @Parameter(title: "类型", default: "")
    var kinds: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var settings = IntentSupport.settings()
        settings.showOnLockScreen = false
        settings.boardFilter = .off
        let selected = IntentSupport.kinds(fromText: kinds)
        if !selected.isEmpty {
            settings.boardKinds = selected
        }
        IntentSupport.saveSettings(settings)

        await BoardActivityManager.shared.dismissAll()
        FloatyBoard.setVisible(false)
        return .result(dialog: "已隐藏锁屏看板")
    }
}

/// 结束锁屏显示（对应 `DismissBoardIntent`）
struct DismissBoardIntent: AppIntent {
    static var title: LocalizedStringResource = "结束锁屏显示"
    static var description: IntentDescription? = IntentDescription("结束当前锁屏看板显示")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await BoardActivityManager.shared.dismissAll()
        FloatyBoard.setVisible(false)
        return .result(dialog: "已结束锁屏显示")
    }
}

/// 切换页面（对应 `PageHomeBoardListIntent`）
struct PageHomeBoardListIntent: AppIntent {
    static var title: LocalizedStringResource = "切换页面"
    static var description: IntentDescription? = IntentDescription("切换锁屏看板的页面")
    static var openAppWhenRun: Bool = false

    /// 翻页步长，默认 +1
    @Parameter(title: "偏移", default: 1)
    var delta: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = IntentSupport.settings()
        let board = FloatyBoard.visibleItems(from: IntentSupport.items(), settings: settings)
        let perPage = max(1, settings.itemsPerPage)
        let pageCount = FloatyBoard.pageCount(board, perPage: perPage)
        guard pageCount > 0 else {
            return .result(dialog: "看板没有内容")
        }
        let next = IntentSupport.nextPageIndex(delta: delta, pageCount: pageCount)
        FloatyBoard.setPageIndex(next)
        IntentSupport.presentBoard()
        return .result(dialog: "第 \(next + 1) 页，共 \(pageCount) 页")
    }
}

/// 切换聚焦项（对应 `FocusHomeBoardIntent`）
struct FocusHomeBoardIntent: AppIntent {
    static var title: LocalizedStringResource = "切换项目"
    static var description: IntentDescription? = IntentDescription("切换锁屏看板当前聚焦的内容")
    static var openAppWhenRun: Bool = false

    /// 移动步长，默认 +1
    @Parameter(title: "偏移", default: 1)
    var delta: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = IntentSupport.settings()
        let board = FloatyBoard.visibleItems(from: IntentSupport.items(), settings: settings)
        let page = FloatyBoard.page(board, index: FloatyBoard.pageIndex(), perPage: max(1, settings.itemsPerPage))
        guard !page.isEmpty else {
            return .result(dialog: "看板没有内容")
        }
        let next = IntentSupport.nextFocusIndex(delta: delta, pageCount: page.count)
        FloatyBoard.setFocusIndex(next)
        IntentSupport.presentBoard()
        return .result(dialog: "聚焦第 \(next + 1) 项：\(page[next].title)")
    }
}

/// 切换聚焦项（对应 `FocusAttentionIntent`）
struct FocusAttentionIntent: AppIntent {
    static var title: LocalizedStringResource = "切换当前项目"
    static var description: IntentDescription? = IntentDescription("切换当前关注的内容")
    static var openAppWhenRun: Bool = false

    /// 移动步长，默认 +1
    @Parameter(title: "偏移", default: 1)
    var delta: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = IntentSupport.settings()
        let board = FloatyBoard.visibleItems(from: IntentSupport.items(), settings: settings)
        let page = FloatyBoard.page(board, index: FloatyBoard.pageIndex(), perPage: max(1, settings.itemsPerPage))
        guard !page.isEmpty else {
            return .result(dialog: "看板没有内容")
        }
        let next = IntentSupport.nextFocusIndex(delta: delta, pageCount: page.count)
        FloatyBoard.setFocusIndex(next)
        IntentSupport.presentBoard()
        return .result(dialog: "聚焦第 \(next + 1) 项：\(page[next].title)")
    }
}

// MARK: - 完成与勾选

/// 完成当前聚焦的内容（对应 `CompleteAttentionIntent`）
struct CompleteAttentionIntent: AppIntent {
    static var title: LocalizedStringResource = "标记完成"
    static var description: IntentDescription? = IntentDescription("把当前聚焦的内容标记为已完成")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let item = IntentSupport.focusedItem() else {
            return .result(dialog: "没有可完成的内容")
        }
        IntentSupport.markCompleted(id: item.id)
        IntentSupport.presentBoard()
        return .result(dialog: "已完成 \(item.title)")
    }
}

/// 完成看板中的某条内容（对应 `CompleteBoardItemIntent`）
struct CompleteBoardItemIntent: AppIntent {
    static var title: LocalizedStringResource = "完成内容"
    static var description: IntentDescription? = IntentDescription("把指定内容标记为已完成")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "内容 ID", default: "")
    var itemID: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let uuid = UUID(uuidString: itemID),
              let item = IntentSupport.items().first(where: { $0.id == uuid }) else {
            return .result(dialog: "未找到该内容")
        }
        IntentSupport.markCompleted(id: uuid)
        IntentSupport.presentBoard()
        return .result(dialog: "已完成 \(item.title)")
    }
}

/// 完成取件码（对应 `CompletePickupLineIntent`）
struct CompletePickupLineIntent: AppIntent {
    static var title: LocalizedStringResource = "完成取件"
    static var description: IntentDescription? = IntentDescription("把指定取件码标记为已取件")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "内容 ID", default: "")
    var itemID: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let uuid = UUID(uuidString: itemID),
              let item = IntentSupport.items().first(where: { $0.id == uuid }) else {
            return .result(dialog: "未找到该内容")
        }
        IntentSupport.markCompleted(id: uuid)
        IntentSupport.presentBoard()
        return .result(dialog: "已完成 \(item.title)")
    }
}

/// 勾选待办子项（对应 `CheckChecklistLineIntent`）
struct CheckChecklistLineIntent: AppIntent {
    static var title: LocalizedStringResource = "勾选子项"
    static var description: IntentDescription? = IntentDescription("勾选或取消勾选待办清单中的子项")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "子项 ID", default: "")
    var entryID: String
    @Parameter(title: "内容 ID", default: "")
    var itemID: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let itemUUID = UUID(uuidString: itemID),
              let lineUUID = UUID(uuidString: entryID) else {
            return .result(dialog: "未找到该子项")
        }
        IntentSupport.toggleChecklist(itemID: itemUUID, lineID: lineUUID)
        IntentSupport.presentBoard()
        return .result(dialog: "已更新清单")
    }
}

/// 勾选看板中的待办子项（对应 `CheckBoardChecklistLineIntent`）
struct CheckBoardChecklistLineIntent: AppIntent {
    static var title: LocalizedStringResource = "勾选看板子项"
    static var description: IntentDescription? = IntentDescription("勾选或取消勾选锁屏看板上的待办子项")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "子项 ID", default: "")
    var entryID: String
    @Parameter(title: "内容 ID", default: "")
    var itemID: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let itemUUID = UUID(uuidString: itemID),
              let lineUUID = UUID(uuidString: entryID) else {
            return .result(dialog: "未找到该子项")
        }
        IntentSupport.toggleChecklist(itemID: itemUUID, lineID: lineUUID)
        IntentSupport.presentBoard()
        return .result(dialog: "已更新清单")
    }
}

// MARK: - 快捷指令提供者（对应 Floaty 的 FloatyShortcuts）

/// 应用内快捷指令提供者。
struct FloatyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddPickupCodeIntent(),
            phrases: [
                "添加取件码到 \(.applicationName)",
                "用 \(.applicationName) 记取件码"
            ],
            shortTitle: "添加取件码",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: AddTodoIntent(),
            phrases: [
                "添加待办到 \(.applicationName)",
                "用 \(.applicationName) 记待办"
            ],
            shortTitle: "添加待办",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: AddTrainTicketIntent(),
            phrases: [
                "添加火车票到 \(.applicationName)",
                "用 \(.applicationName) 记火车票"
            ],
            shortTitle: "添加火车票",
            systemImageName: "train.side.front.car"
        )
        AppShortcut(
            intent: AddFlightTicketIntent(),
            phrases: [
                "添加机票到 \(.applicationName)",
                "用 \(.applicationName) 记机票"
            ],
            shortTitle: "添加机票",
            systemImageName: "airplane"
        )
        AppShortcut(
            intent: RecognizeTextIntent(),
            phrases: [
                "用 \(.applicationName) 识别文本"
            ],
            shortTitle: "识别文本",
            systemImageName: "text.viewfinder"
        )
    }
}
