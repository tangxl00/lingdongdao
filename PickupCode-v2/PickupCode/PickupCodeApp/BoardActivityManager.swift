import ActivityKit
import Foundation
import os

/// 锁屏看板 Live Activity 管理器（对应 Floaty 的「此刻」看板）。
///
/// - 静态属性：看板标题 + 过滤说明
/// - 动态状态：当前页卡片、页码、聚焦项、倒计时
final class BoardActivityManager {

    static let shared = BoardActivityManager()

    private let logger = Logger(subsystem: "com.yourteam.pickupcode", category: "BoardActivity")

    private var refreshTask: Task<Void, Never>?

    private init() {}

    var activeActivities: [Activity<FloatyAttributes>] {
        Activity<FloatyAttributes>.activities
    }

    /// 启动 / 更新看板 Live Activity。
    /// - Parameters:
    ///   - items: 全部内容
    ///   - settings: 过滤与显示设置
    ///   - pageIndex: 目标页
    ///   - focusIndex: 页内聚焦项
    func present(items: [FloatyItem],
                 settings: FloatySettings,
                 pageIndex: Int,
                 focusIndex: Int,
                 now: Date = Date()) {
        let boardItems = FloatyBoard.visibleItems(from: items, settings: settings, now: now)
        guard !boardItems.isEmpty else {
            Task { await dismissAll() }
            return
        }

        let perPage = max(1, settings.itemsPerPage)
        let pageCount = FloatyBoard.pageCount(boardItems, perPage: perPage)
        let clampedPage = min(max(0, pageIndex), max(0, pageCount - 1))
        let pageItems = FloatyBoard.page(boardItems, index: clampedPage, perPage: perPage)
        guard !pageItems.isEmpty else { return }

        let clampedFocus = min(max(0, focusIndex), pageItems.count - 1)
        let focused = pageItems[clampedFocus]

        let cards = pageItems.map { item in
            BoardCard(item: item,
                      dueText: FloatyDate.timeRemainingText(from: item.referenceDate, now: now),
                      isExpiringSoon: FloatyDate.isExpiringSoon(item.referenceDate, now: now))
        }

        let state = FloatyAttributes.ContentState(
            cards: cards,
            pageIndex: clampedPage,
            pageCount: pageCount,
            focusIndex: clampedFocus,
            timeRemainingText: FloatyDate.timeRemainingText(from: focused.referenceDate, now: now),
            isExpiringSoon: FloatyDate.isExpiringSoon(focused.referenceDate, now: now),
            isCompleted: focused.isCompleted,
            note: focused.note
        )

        let attributes = FloatyAttributes(
            title: "此刻",
            filterDescription: filterDescription(settings: settings)
        )

        Task {
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                // 已有看板活动 → 直接更新
                if !activeActivities.isEmpty {
                    for activity in activeActivities {
                        await activity.update(ActivityContent(state: state, staleDate: nil))
                    }
                } else {
                    _ = try? Activity<FloatyAttributes>.request(
                        attributes: attributes,
                        content: ActivityContent(state: state, staleDate: nil)
                    )
                }
            }
            startRefreshLoop()
        }
    }

    /// 过滤说明文案
    private func filterDescription(settings: FloatySettings) -> String {
        switch settings.boardFilter {
        case .off:
            return "未在锁屏显示"
        case .only:
            let names = FloatyKind.allCases
                .filter { settings.boardKinds.contains($0) }
                .map(\.displayName)
            return names.isEmpty ? "未选择类型" : "仅显示：\(names.joined(separator: "、"))"
        case .except:
            let names = FloatyKind.allCases
                .filter { settings.boardKinds.contains($0) }
                .map(\.displayName)
            return names.isEmpty ? "显示全部类型" : "排除：\(names.joined(separator: "、"))"
        }
    }

    /// 结束全部看板活动
    func dismissAll() async {
        for activity in activeActivities {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// 周期刷新倒计时（App 存活期间每 60 秒一次）
    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let store = FloatyStore.shared
                self.present(items: store.items,
                             settings: store.settings,
                             pageIndex: store.boardPageIndex,
                             focusIndex: store.boardFocusIndex)
            }
        }
    }
}
