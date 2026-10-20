import ActivityKit
import Foundation
import os

/// 封装 ActivityKit：启动、更新、结束 Live Activity；处理超时兜底。
/// 接口签名与《技术架构设计文档》第 2 节一致。
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private let logger = Logger(subsystem: "com.yourteam.pickupcode", category: "LiveActivity")

    /// App 进程存活期间的超时兜底任务（按取件码索引）
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    /// 获取当前活跃的 Activity 列表（通常应只有 0 或 1 个；不同取件码可并存，灵动岛展示最近一个）。
    var activeActivities: [Activity<PickupCodeAttributes>] {
        Activity<PickupCodeAttributes>.activities
    }

    /// 启动新的 Live Activity；若已存在同 code 的 Activity，先结束旧再启动新（架构文档 P2 风险缓解 + 验收 B-02）。
    /// 其他取件码的活动不受影响（锁屏可同时展示多个，灵动岛显示最近的一个）。
    func startActivity(attributes: PickupCodeAttributes, state: PickupCodeAttributes.ContentState) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.activitiesDisabled
        }

        // 去重：同 code 的旧 Activity 先结束
        let duplicates = activeActivities.filter { $0.attributes.code == attributes.code }
        if !duplicates.isEmpty {
            logger.notice("存在同 code 旧 Activity，先结束再启动：\(attributes.code, privacy: .public)")
            Task {
                for activity in duplicates {
                    await activity.end(using: nil, dismissalPolicy: .immediate)
                }
            }
        }

        _ = try Activity<PickupCodeAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        )
        logger.info("已启动 Live Activity：\(attributes.code, privacy: .public)")
        scheduleTimeoutFallback(for: attributes)
    }

    /// 更新当前全部 Activity 的 ContentState（如倒计时刷新、过期状态变更）。
    func updateActivity(state: PickupCodeAttributes.ContentState) async {
        for activity in activeActivities {
            await activity.update(using: state)
        }
    }

    /// 更新指定取件码的 Activity。
    func updateActivity(forCode code: String, state: PickupCodeAttributes.ContentState) async {
        for activity in activeActivities where activity.attributes.code == code {
            await activity.update(using: state)
        }
    }

    /// 用户点击"取完"后调用；dismissalPolicy 设为 immediate。
    func endActivity() async {
        for activity in activeActivities {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
        cancelTimeoutTasks()
        logger.info("已结束全部 Live Activity")
    }

    /// 结束指定取件码的 Activity（用户点击"已取件"）。
    func endActivity(forCode code: String) async {
        for activity in activeActivities where activity.attributes.code == code {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
        timeoutTasks.removeValue(forKey: code)?.cancel()
        logger.info("已结束 Live Activity：\(code, privacy: .public)")
    }

    /// 按各自过期时间刷新所有 Activity 的倒计时文案与过期警示。
    func refreshTimeRemaining() async {
        for activity in activeActivities {
            let expiryDate = activity.attributes.expiry.flatMap(PickupCodeDate.date(fromISO:))
            let state = PickupCodeAttributes.ContentState(
                timeRemainingText: PickupCodeDate.timeRemainingText(from: expiryDate),
                isExpiringSoon: PickupCodeDate.isExpiringSoon(expiryDate),
                isCompleted: false
            )
            await activity.update(using: state)
        }
    }

    // MARK: - 超时兜底

    /// App 进程存活期间，在「过期时间」或「系统 8 小时上限」中较早到达的时刻做最后状态刷新，
    /// 随后主动结束 Activity，避免"僵死"展示。
    /// 若 App 已被系统回收：Live Activity 由系统按 8 小时上限自动移除，
    /// 历史记录状态由主 App 下次前台激活时的对账逻辑兜底（见 HistoryStore.reconcile(activeCodes:)）。
    private func scheduleTimeoutFallback(for attributes: PickupCodeAttributes) {
        let code = attributes.code
        timeoutTasks[code]?.cancel()

        let expiryDate = attributes.expiry.flatMap(PickupCodeDate.date(fromISO:))
        let systemDeadline = Date().addingTimeInterval(PickupCodeStorage.activityLifetime)
        let fallbackDate = min(expiryDate ?? .distantFuture, systemDeadline)

        let delay = max(1, fallbackDate.timeIntervalSinceNow)
        timeoutTasks[code] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let finalState = PickupCodeAttributes.ContentState(
                timeRemainingText: PickupCodeDate.timeRemainingText(from: expiryDate),
                isExpiringSoon: true,
                isCompleted: false
            )
            await self.updateActivity(forCode: code, state: finalState)
            // 刷新后保留 60 秒供用户查看，再主动结束
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            await self.endActivity(forCode: code)
        }
    }

    private func cancelTimeoutTasks() {
        for (_, task) in timeoutTasks { task.cancel() }
        timeoutTasks.removeAll()
    }

    enum LiveActivityError: LocalizedError {
        case activitiesDisabled

        var errorDescription: String? {
            switch self {
            case .activitiesDisabled:
                return "Live Activity 已被系统或用户关闭"
            }
        }
    }
}
