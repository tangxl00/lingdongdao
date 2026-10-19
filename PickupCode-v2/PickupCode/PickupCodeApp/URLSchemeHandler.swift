import Foundation
import os

/// 解析快捷指令传入的 pickupcode:// URL。
/// 与《技术架构设计文档》第 7 节参数表逐项一致（唯一接口契约）。
///
/// 契约示例：
/// `pickupcode://show?code=123456&station=菜鸟驿站&courier=顺丰&expiry=2026-10-10T22:00:00+08:00&note=请尽快取件`
///
/// 校验规则（与架构文档第 7 节逐条对应）：
/// 1. code 为空或仅空白字符 → 拒绝启动，记录日志，静默失败（不弹窗打扰用户）。
/// 2. station 为空 → 使用默认值"未知驿站"。
/// 3. expiry 格式非法 → 忽略该字段，不展示倒计时/过期提示。
/// 4. expiry 已过期 → 仍启动 Live Activity，isExpiringSoon 标记为 true，UI 展示红色警示。
/// 5. 所有参数值 URL Decode（URLComponents.queryItems 已自动完成百分号解码）。
/// 6. 参数长度限制：code ≤ 20、station ≤ 50、courier ≤ 20、note ≤ 100 字符，超长截断。
enum URLSchemeHandler {

    struct ParsedPickupURL: Equatable {
        let code: String
        let station: String
        let courier: String?
        let expiry: String?
        let note: String?
    }

    static let scheme = "pickupcode"
    static let defaultStation = "未知驿站"

    private static let logger = Logger(subsystem: "com.yourteam.pickupcode", category: "URLScheme")

    /// 解析并校验 URL。失败返回 nil（调用方静默忽略）。
    static func parse(_ url: URL) -> ParsedPickupURL? {
        guard url.scheme?.lowercased() == scheme else {
            logger.debug("忽略非 pickupcode scheme 的 URL")
            return nil
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            logger.error("URL 无法解析为组件：\(url.absoluteString, privacy: .public)")
            return nil
        }

        // 仅处理 show 动作（done 动作由 parseDoneCode 单独处理）
        guard components.host?.lowercased() == "show" else {
            logger.debug("忽略非 show 动作的 URL：\(components.host ?? "nil", privacy: .public)")
            return nil
        }

        func firstValue(_ keys: [String]) -> String? {
            for key in keys {
                if let item = components.queryItems?.first(where: { $0.name == key }),
                   let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        // 规则 1：code 必填，空/纯空白拒绝
        guard let rawCode = firstValue(["code"]) else {
            logger.error("URL 缺少有效 code 参数，拒绝处理：\(url.absoluteString, privacy: .public)")
            return nil
        }
        // 规则 6：长度限制与截断
        let code = String(rawCode.prefix(20))

        // 规则 2：station 默认值
        let station = firstValue(["station"]).map { String($0.prefix(50)) } ?? defaultStation

        // courier（兼容产品文档早期草稿的 carrier 拼写，仅作容错，契约参数名仍为 courier）
        let courier = firstValue(["courier", "carrier"]).map { String($0.prefix(20)) }

        // 规则 3：expiry 非法则忽略；兼容早期草稿的 expire=Unix 秒级时间戳
        let expiry = firstValue(["expiry", "expire"]).flatMap(normalizedExpiry(from:))

        let note = firstValue(["note"]).map { String($0.prefix(100)) }

        return ParsedPickupURL(
            code: code,
            station: station,
            courier: courier,
            expiry: expiry,
            note: note
        )
    }

    /// 规则 3/4：expiry 归一化为标准 ISO 8601（带时区偏移）；无法解析返回 nil（忽略该字段）。
    static func normalizedExpiry(from raw: String) -> String? {
        if let date = PickupCodeDate.date(fromISO: raw) {
            return PickupCodeDate.normalizeISO(date)
        }
        // 兼容 Unix 时间戳：秒级（10 位）或毫秒级（13 位，截取前 10 位）
        if raw.allSatisfy(\.isNumber), raw.count >= 10 {
            let secondsText = raw.count >= 13 ? String(raw.prefix(10)) : raw
            if let seconds = TimeInterval(secondsText), seconds > 1_000_000_000 {
                return PickupCodeDate.normalizeISO(Date(timeIntervalSince1970: seconds))
            }
        }
        return nil
    }

    /// 组装 App 内测试/跳转用的 pickupcode:// URL。
    static func makeShowURL(code: String, station: String? = nil, courier: String? = nil, expiry: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "show"
        var items = [URLQueryItem(name: "code", value: code)]
        if let station { items.append(URLQueryItem(name: "station", value: station)) }
        if let courier { items.append(URLQueryItem(name: "courier", value: courier)) }
        if let expiry { items.append(URLQueryItem(name: "expiry", value: expiry)) }
        components.queryItems = items
        return components.url
    }

    /// 解析灵动岛"已取件"按钮回跳的 pickupcode://done?code=... URL，返回取件码。
    /// 失败返回 nil（调用方静默忽略）。
    static func parseDoneCode(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "done",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let raw = components.queryItems?.first(where: { $0.name == "code" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return String(raw.prefix(20))
    }
}
