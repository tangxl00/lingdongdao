import ActivityKit
import Combine
import Foundation
import os

/// 历史记录读写：UserDefaults + Codable（《技术架构设计文档》第 4 节选型结论）。
///
/// - 数据量极小（单条约 200B，上限 500 条），内存过滤足够高效；
/// - 付费开发者账号配置 App Group（group.com.yourteam.pickupcode）后，主 App 与 Widget 自动共享数据；
/// - 免费 Apple ID 无 App Group：主 App 读写自身容器不受影响；Widget 侧"已取件"标记无法跨进程同步，
///   由 App 前台激活时的对账逻辑兜底（见 reconcile(activeCodes:)）。
final class HistoryStore: ObservableObject, PickupCodeStoreProtocol {

    static let shared = HistoryStore()

    /// 记录条数上限（防止 UserDefaults 无限增长）
    private static let maxRecords = 500

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.yourteam.pickupcode", category: "HistoryStore")

    @Published private(set) var records: [PickupCode] = []

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if let suite = UserDefaults(suiteName: PickupCodeStorage.appGroupID) {
            self.defaults = suite
        } else {
            self.defaults = .standard
        }
        records = Self.load(from: self.defaults)
    }

    // MARK: - 读写

    private static func load(from defaults: UserDefaults) -> [PickupCode] {
        guard let data = defaults.data(forKey: PickupCodeStorage.historyKey) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([PickupCode].self, from: data)
            return decoded.sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    private func persist() {
        let trimmed = Array(records.prefix(Self.maxRecords))
        if trimmed.count != records.count {
            logger.notice("历史记录超过 \(Self.maxRecords) 条，已裁剪最旧的记录")
        }
        do {
            let data = try JSONEncoder().encode(trimmed)
            defaults.set(data, forKey: PickupCodeStorage.historyKey)
        } catch {
            logger.error("历史记录编码失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - PickupCodeStoreProtocol 实现

    func loadAll() -> [PickupCode] {
        records
    }

    /// 新记录插入，或同 code 未完结记录原地更新（验收 B-02：重复取件码不产生重复记录）。
    func insertOrUpdate(_ record: PickupCode) {
        if let index = records.firstIndex(where: { $0.code == record.code && !$0.isCompleted && !$0.isExpired }) {
            var merged = record
            merged.id = records[index].id
            records[index] = merged
        } else {
            records.insert(record, at: 0)
        }
        persist()
    }

    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    func markCompleted(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].isCompleted = true
        records[index].isExpired = false
        persist()
    }

    func markExpired(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].isExpired = true
        persist()
    }

    func clearCompleted() {
        records.removeAll { $0.isCompleted || $0.isExpired }
        persist()
    }

    /// 清空全部历史（含进行中记录）
    func clearAll() {
        records.removeAll()
        persist()
    }

    /// 标记某取件码的 Live Activity 已成功启动（对账依据）。
    func markActivityStarted(code: String) {
        guard let index = records.firstIndex(where: { $0.code == code && !$0.isCompleted && !$0.isExpired }) else { return }
        records[index].didStartActivity = true
        persist()
    }

    /// 按取件码标记已取件（灵动岛兜底跳转路径使用）。
    func markCompleted(code: String) {
        guard let index = records.firstIndex(where: { $0.code == code && !$0.isCompleted && !$0.isExpired }) else { return }
        records[index].isCompleted = true
        persist()
    }

    // MARK: - 便捷查询

    /// 进行中的记录（灵动岛/主界面正在展示的取件码）
    var activeRecords: [PickupCode] {
        records.filter { !$0.isCompleted && !$0.isExpired }
    }

    // MARK: - 对账（前台激活时调用）

    /// 与 ActivityKit 当前活跃列表对账，补齐"灵动岛侧已结束但主 App 尚不知情"的记录：
    /// - 活动仍在 → 保持进行中；
    /// - 活动已消失且 App Group 中有"已取件"标记（付费账号场景）→ 标记已取件；
    /// - 活动已消失且距创建约 7.5 小时以上 → 判定为系统 8 小时超时；
    /// - 活动已消失且时间尚早 → 判定为用户已在灵动岛点击"已取件"
    ///   （免费账号无 App Group 时的兜底启发式；用户手动划掉 Activity 也会归入此类）。
    func reconcile(activeCodes: Set<String>, now: Date = Date()) {
        var changed = false
        for index in records.indices {
            let record = records[index]
            guard !record.isCompleted, !record.isExpired,
                  record.didStartActivity,
                  !activeCodes.contains(record.code) else { continue }

            if let completedAt = defaults.object(forKey: PickupCodeStorage.completedMarkerPrefix + record.code) as? Date {
                records[index].isCompleted = true
                logger.info("对账：\(record.code, privacy: .public) 已取件（标记于 \(completedAt, privacy: .public)）")
            } else if now.timeIntervalSince(record.createdAt) >= PickupCodeStorage.activityLifetime - 1800 {
                records[index].isExpired = true
                logger.info("对账：\(record.code, privacy: .public) 判定为超时")
            } else {
                records[index].isCompleted = true
                logger.info("对账：\(record.code, privacy: .public) 判定为已在灵动岛取件")
            }
            changed = true
        }
        if changed { persist() }
    }

    /// 便捷入口：读取 ActivityKit 当前活跃取件码后对账，并顺带刷新倒计时。
    func reconcileWithSystem() {
        let activeCodes = Set(Activity<PickupCodeAttributes>.activities.map { $0.attributes.code })
        reconcile(activeCodes: activeCodes)
        Task { await LiveActivityManager.shared.refreshTimeRemaining() }
    }
}
