import Foundation

/// 锁屏看板的状态（页码 / 聚焦项），存于共享 UserDefaults，供 App Intents 与主 App 共同修改。
enum FloatyBoard {

    /// 当前页下标（从 0 开始）
    static let pageIndexKey = "floaty.board.pageIndex"
    /// 当前页内聚焦项下标
    static let focusIndexKey = "floaty.board.focusIndex"
    /// 看板是否显示
    static let visibleKey = "floaty.board.visible"

    static func pageIndex() -> Int {
        Int(FloatyStorage.sharedDefaults().integer(forKey: pageIndexKey))
    }

    static func setPageIndex(_ value: Int) {
        FloatyStorage.sharedDefaults().set(max(0, value), forKey: pageIndexKey)
    }

    static func focusIndex() -> Int {
        Int(FloatyStorage.sharedDefaults().integer(forKey: focusIndexKey))
    }

    static func setFocusIndex(_ value: Int) {
        FloatyStorage.sharedDefaults().set(max(0, value), forKey: focusIndexKey)
    }

    static func isVisible() -> Bool {
        FloatyStorage.sharedDefaults().bool(forKey: visibleKey)
    }

    static func setVisible(_ value: Bool) {
        FloatyStorage.sharedDefaults().set(value, forKey: visibleKey)
    }

    static func reset() {
        let defaults = FloatyStorage.sharedDefaults()
        defaults.set(0, forKey: pageIndexKey)
        defaults.set(0, forKey: focusIndexKey)
        defaults.set(false, forKey: visibleKey)
    }

    /// 按过滤规则筛出看板要展示的内容（并按类型权重与时间排序）。
    static func visibleItems(from items: [FloatyItem],
                             settings: FloatySettings,
                             now: Date = Date()) -> [FloatyItem] {
        let active = items.filter { !$0.isCompleted && !$0.isExpired }

        let filtered: [FloatyItem]
        switch settings.boardFilter {
        case .off:
            filtered = []
        case .only:
            filtered = active.filter { settings.boardKinds.contains($0.kind) }
        case .except:
            filtered = active.filter { !settings.boardKinds.contains($0.kind) }
        }

        return filtered.sorted { lhs, rhs in
            if lhs.kind.sortWeight != rhs.kind.sortWeight {
                return lhs.kind.sortWeight < rhs.kind.sortWeight
            }
            let lhsDate = lhs.referenceDate ?? lhs.createdAt
            let rhsDate = rhs.referenceDate ?? rhs.createdAt
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// 分页
    static func page<T>(_ items: [T], index: Int, perPage: Int) -> [T] {
        guard perPage > 0, !items.isEmpty else { return [] }
        let start = index * perPage
        guard start < items.count else { return [] }
        let end = min(start + perPage, items.count)
        return Array(items[start..<end])
    }

    static func pageCount(_ items: [FloatyItem], perPage: Int) -> Int {
        guard perPage > 0, !items.isEmpty else { return 0 }
        return (items.count + perPage - 1) / perPage
    }
}
