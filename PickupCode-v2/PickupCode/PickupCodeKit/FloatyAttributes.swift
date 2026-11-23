import ActivityKit
import Foundation

/// 锁屏看板上的一张卡片（写入 Live Activity 动态状态）。
struct BoardCard: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: FloatyKind
    /// 主标题：取件码 / 车次 / 航班号 / 待办标题
    var title: String
    /// 副标题：取件地点 / 起→止
    var subtitle: String?
    /// 详情行
    var detail: String?
    /// 剩余时间文案
    var dueText: String
    var isCompleted: Bool
    var isExpiringSoon: Bool
    var checklistDone: Int
    var checklistTotal: Int

    init(item: FloatyItem, dueText: String, isExpiringSoon: Bool) {
        self.id = item.id
        self.kind = item.kind
        self.title = item.title
        self.subtitle = item.displaySubtitle
        self.detail = item.detailText
        self.dueText = dueText
        self.isCompleted = item.isCompleted
        self.isExpiringSoon = isExpiringSoon
        self.checklistDone = item.checklistDone
        self.checklistTotal = item.checklistTotal
    }
}

/// 锁屏看板 Live Activity 的静态属性与动态状态。
///
/// 对应 Floaty 的「此刻」看板：静态属性是看板标题与过滤说明，
/// 动态状态携带当前页卡片、页码、页内聚焦项与倒计时。
struct FloatyAttributes: ActivityAttributes {

    /// 看板标题
    let title: String

    /// 类型过滤说明（"仅显示：取件码、火车票"）
    let filterDescription: String

    /// ContentState：活动中可更新的动态数据
    struct ContentState: Codable, Hashable {
        /// 当前页的卡片
        var cards: [BoardCard]
        /// 第几页（从 0 开始）
        var pageIndex: Int
        /// 总页数
        var pageCount: Int
        /// 页内聚焦项下标
        var focusIndex: Int
        /// 聚焦卡片的剩余时间文案
        var timeRemainingText: String
        /// 聚焦卡片是否即将到期
        var isExpiringSoon: Bool
        /// 聚焦卡片是否已完成
        var isCompleted: Bool
        /// 聚焦卡片的备注
        var note: String?
    }
}
