import Foundation

/// 存储相关常量（主 App 与 Widget Extension 共享）。
enum PickupCodeStorage {
    /// App Group 标识（与《技术架构设计文档》第 3 节一致）。
    /// 付费开发者账号配置该 App Group 后，主 App 与 Widget 自动共享数据；
    /// 免费 Apple ID 无法配置 App Group，各进程读写各自容器，不影响核心展示功能。
    static let appGroupID = "group.com.yourteam.pickupcode"

    /// 历史记录在 UserDefaults 中的键
    static let historyKey = "pickupcode.history"

    /// "已取件"完成标记键前缀（Widget 侧按钮写入，主 App 对账时读取；仅在 App Group 生效时跨进程可见）
    static let completedMarkerPrefix = "pickupcode.completed."

    /// Live Activity 系统展示上限（8 小时）
    static let activityLifetime: TimeInterval = 8 * 3600
}

/// 存储抽象协议，解耦主 App 与具体存储实现。
/// 当前实现：HistoryStore（UserDefaults + Codable，见主 App target）。
protocol PickupCodeStoreProtocol {
    func loadAll() -> [PickupCode]
    func insertOrUpdate(_ record: PickupCode)
    func deleteRecord(id: UUID)
    func markCompleted(id: UUID)
    func markExpired(id: UUID)
    func clearCompleted()
}
