import Foundation

/// 时间工具（主 App 与 Widget Extension 共用）。
enum FloatyDate {

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

    /// 剩余时间描述（由 App 计算后写入 ContentState.timeRemainingText）
    static func timeRemainingText(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "尽快处理" }
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

    /// 解析"出发时间"文案：
    /// - 英文：`Oct 24 14:30`、`Oct 24`
    /// - 中文：`10月24日14:30`
    static func parseDeparture(_ text: String, now: Date = Date()) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let iso = date(fromISO: trimmed) { return iso }

        let enFormats = ["MMM d HH:mm", "MMM d, HH:mm", "MMM d h:mm a", "MMM d"]
        for format in enFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let parsed = formatter.date(from: trimmed) { return parsed }
        }

        let normalized = trimmed
            .replacingOccurrences(of: "月", with: " ")
            .replacingOccurrences(of: "日", with: " ")
            .replacingOccurrences(of: "号", with: " ")
        let zhFormats = ["M d HH:mm", "M d H:mm", "M d"]
        for format in zhFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let parsed = formatter.date(from: normalized) { return parsed }
        }
        return nil
    }

    /// `09:00` → 今天的 09:00
    static func parseTimeOnly(_ text: String, now: Date = Date()) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let time = formatter.date(from: trimmed) else { return nil }
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: calendar.component(.hour, from: time),
            minute: calendar.component(.minute, from: time),
            second: 0,
            of: now
        )
    }
}
