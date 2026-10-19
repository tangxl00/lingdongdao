import Foundation

/// 取件码实体：历史记录数据模型（主 App 与 Widget 共享）。
///
/// 基础字段与《技术架构设计文档》第 1 节 PickupCodeKit/PickupCode.swift 一致
/// （code、station、courier、expiry、createdAt、isCompleted），
/// 另为 URL 契约中的 note 参数、稳定标识与状态判定补充了 id / note / isExpired / didStartActivity 字段。
struct PickupCode: Codable, Identifiable, Hashable {
    var id: UUID
    var code: String
    var station: String
    var courier: String?
    /// 过期时间，标准 ISO 8601 字符串（带时区偏移）
    var expiry: String?
    /// 附加备注（URL 契约可选参数）
    var note: String?
    var createdAt: Date
    var isCompleted: Bool
    /// 已超时（Live Activity 超过系统 8 小时上限自动消失，未被用户确认取件）
    var isExpired: Bool
    /// 是否成功启动过 Live Activity（对账时用于区分"从未启动"与"已结束"）
    var didStartActivity: Bool

    init(id: UUID = UUID(),
         code: String,
         station: String,
         courier: String? = nil,
         expiry: String? = nil,
         note: String? = nil,
         createdAt: Date = Date(),
         isCompleted: Bool = false,
         isExpired: Bool = false,
         didStartActivity: Bool = false) {
        self.id = id
        self.code = code
        self.station = station
        self.courier = courier
        self.expiry = expiry
        self.note = note
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.isExpired = isExpired
        self.didStartActivity = didStartActivity
    }

    /// 过期时间解析结果（expiry 非法时为 nil）
    var expiryDate: Date? {
        guard let expiry, !expiry.isEmpty else { return nil }
        return PickupCodeDate.date(fromISO: expiry)
    }

    /// 状态显示文案
    var statusText: String {
        if isCompleted { return "已取件" }
        if isExpired { return "已超时" }
        return "进行中"
    }
}

/// 取件码相关的日期/时间工具（App 与 Widget 共用）。
enum PickupCodeDate {

    /// ISO 8601 解析。
    /// 兼容：带/不带毫秒、带/不带时区偏移；无时区时按当前时区处理。
    /// 另兼容 URL 传输中 ISO 时间戳的 "+" 被还原为空格的情况。
    static func date(fromISO string: String) -> Date? {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 形如 "2026-10-10T22:00:00 08:00" 的空格偏移还原为 "+08:00"
        if let range = text.range(of: #"(\d{2}:\d{2}:\d{2})\s([+-]\d{2}:\d{2})$"#, options: .regularExpression) {
            let fixed = text[range].replacingOccurrences(of: " ", with: "+")
            text.replaceSubrange(range, with: fixed)
        }

        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]
        if let date = internetDateTime.date(from: text) { return date }

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: text) { return date }

        let noTimeZone = DateFormatter()
        noTimeZone.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        noTimeZone.locale = Locale(identifier: "en_US_POSIX")
        noTimeZone.timeZone = .current
        return noTimeZone.date(from: text)
    }

    /// 归一化为标准 ISO 8601 输出（带时区偏移，如 2026-10-10T22:00:00+08:00）
    static func normalizeISO(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// 剩余时间描述（契约：由 App 计算后写入 ContentState.timeRemainingText）
    static func timeRemainingText(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "尽快取件" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "已到期" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "剩余 \(hours) 小时 \(minutes) 分" }
        if minutes > 0 { return "剩余 \(minutes) 分钟" }
        return "即将到期"
    }

    /// 是否即将过期（已过期或剩余不足 1 小时 → UI 变色警示）
    static func isExpiringSoon(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return date.timeIntervalSince(now) <= 3600
    }
}
