import Foundation

/// 应用设置（主 App 与 App Intents 共享）。
struct FloatySettings: Codable, Hashable {

    // MARK: - 锁屏显示设置（对应 Floaty 的 Display settings）

    /// 显示时间
    var showTime: Bool = true
    /// 紧凑视图
    var compactView: Bool = false
    /// 最小化显示
    var minimizeDisplay: Bool = false
    /// 最小化时隐藏内容
    var hideContentWhenMinimized: Bool = false
    /// 显示详情
    var showDetails: Bool = true
    /// 同地点内排序
    var sortWithinLocation: Bool = true
    /// 在卡片上直接显示完成按钮
    var showCompleteButton: Bool = true

    // MARK: - 锁屏看板

    /// 是否在锁屏显示看板
    var showOnLockScreen: Bool = false
    /// 看板类型过滤方式
    var boardFilter: BoardKindFilter = .off
    /// 参与过滤的类型集合
    var boardKinds: Set<FloatyKind> = []

    // MARK: - 自动添加

    /// 内置取件识别（对应 "Built-in pickup recognition"）
    var builtinPickupEnabled: Bool = true
    /// 打开 App 时识别剪贴板（对应 "Scan clipboard on open"）
    var scanClipboardOnOpen: Bool = false
    /// 每日取件提醒
    var dailyReminder: Bool = false
    /// 每日提醒时间（HH:mm）
    var dailyReminderTime: String = "09:00"

    // MARK: - 外观

    /// 界面语言：zh-Hans / en
    var language: String = "zh-Hans"
    /// 外观：system / light / dark
    var appearance: String = "system"

    /// 每页卡片数量（锁屏看板）
    var itemsPerPage: Int = 3

    /// 看板筛选后的类型集合（off → 空；only → 所选；except → 排除所选）
    var effectiveKinds: Set<FloatyKind> {
        switch boardFilter {
        case .off:
            return []
        case .only:
            return boardKinds
        case .except:
            return Set(FloatyKind.allCases).subtracting(boardKinds)
        }
    }
}
