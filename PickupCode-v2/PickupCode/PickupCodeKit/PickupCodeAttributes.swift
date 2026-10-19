import ActivityKit
import Foundation

/// Live Activity 静态属性与动态状态定义。
/// 与《取件码灵动岛 App — 技术架构设计文档》第 2 节接口签名逐项一致。
struct PickupCodeAttributes: ActivityAttributes {

    /// 取件码：创建后不可变（静态属性）
    let code: String

    /// 驿站/代收点名称（静态属性）
    let station: String

    /// 快递公司（静态属性，可选）
    let courier: String?

    /// 过期时间 ISO 字符串（静态属性，用于本地超时判断）
    let expiry: String?

    /// ContentState：活动中可更新的动态数据
    struct ContentState: Codable, Hashable {
        /// 剩余时间描述（如"剩余 2 小时"），由 App 计算后写入
        var timeRemainingText: String

        /// 是否即将过期（用于 UI 变色警示）
        var isExpiringSoon: Bool

        /// 用户是否已点击"取完"
        var isCompleted: Bool
    }
}
