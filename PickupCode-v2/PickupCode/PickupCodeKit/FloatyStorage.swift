import Foundation

/// 存储相关常量（主 App 与 Widget Extension 共享）。
enum FloatyStorage {
    /// App Group 标识（与 entitlements 中的声明保持一致）。
    /// 免费 Apple ID 无法配置 App Group，各进程读写各自容器，不影响核心展示功能。
    static let appGroupID = "group.com.yourteam.pickupcode"

    /// 历史记录在 UserDefaults 中的键
    static let historyKey = "floaty.items"

    /// 识别模板在 UserDefaults 中的键
    static let templatesKey = "floaty.templates"

    /// 设置项在 UserDefaults 中的键
    static let settingsKey = "floaty.settings"

    /// "已完成"标记键前缀（Widget 侧按钮写入，主 App 对账时读取）
    static let completedMarkerPrefix = "floaty.completed."

    /// 快捷指令请求打开的添加类型（ComposeAttentionIntent 等写入，主 App 读取后跳到对应表单）
    static let pendingComposeKindKey = "floaty.pendingComposeKind"

    /// Live Activity 系统展示上限（8 小时）
    static let activityLifetime: TimeInterval = 8 * 3600

    /// URL scheme
    static let urlScheme = "floaty"

    /// 共享 UserDefaults（无 App Group 时回退到 .standard）
    static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

/// 存储抽象协议，解耦主 App 与具体存储实现。
protocol FloatyStoreProtocol {
    func loadAll() -> [FloatyItem]
    func insertOrUpdate(_ item: FloatyItem)
    func deleteRecord(id: UUID)
    func markCompleted(id: UUID)
    func markExpired(id: UUID)
    func clearCompleted()
}
