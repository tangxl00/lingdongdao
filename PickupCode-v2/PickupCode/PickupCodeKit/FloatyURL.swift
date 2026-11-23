import Foundation

/// URL 契约解析（快捷指令 / 分享菜单 / 深度链接传入内容）。
///
/// 主契约（scheme `floaty`）：
/// ```
/// floaty://show?kind=pickup&code=886677&station=菜鸟驿站&courier=顺丰&expiry=2026-10-10T22:00:00+08:00
/// floaty://show?kind=train&train=G9527&from=北京南&to=上海虹桥&departure=2026-10-24T14:30:00+08:00&seat=12A&car=5&gate=B12
/// floaty://show?kind=flight&flight=CA9527&from=PEK&to=PVG&departure=...&arrival=...&terminal=T3&seat=32A&gate=C12
/// floaty://show?kind=todo&headline=买牛奶&note=冰箱&due=2026-10-24T20:00:00+08:00
/// floaty://done?id=<UUID>
/// ```
///
/// 兼容旧契约（scheme `pickupcode`）：`pickupcode://show?code=...&station=...&expiry=...`
enum FloatyURL {

    /// 解析出的一条内容
    struct ParsedItem: Equatable {
        var kind: FloatyKind = .pickup
        var title: String = ""
        var subtitle: String? = nil
        var detail: String? = nil
        var from: String? = nil
        var to: String? = nil
        var departure: String? = nil
        var arrival: String? = nil
        var due: String? = nil
        var seat: String? = nil
        var car: String? = nil
        var gate: String? = nil
        var terminal: String? = nil
        var note: String? = nil
    }

    static let scheme = FloatyStorage.urlScheme
    static let legacyScheme = "pickupcode"

    private static let maxTitle = 60
    private static let maxSubtitle = 80
    private static let maxDetail = 40
    private static let maxNote = 200

    /// 解析 `show` 动作；失败返回 nil（调用方静默忽略）。
    static func parse(_ url: URL) -> ParsedItem? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = components.scheme?.lowercased()
        guard scheme == self.scheme || scheme == legacyScheme else { return nil }
        guard components.host?.lowercased() == "show" else { return nil }

        func value(_ keys: [String]) -> String? {
            for key in keys {
                if let item = components.queryItems?.first(where: { $0.name.lowercased() == key }),
                   let raw = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !raw.isEmpty {
                    return raw
                }
            }
            return nil
        }

        var parsed = ParsedItem()

        // 类型
        if let rawKind = value(["kind", "type"])?.lowercased(),
           let kind = FloatyKind(rawValue: rawKind) {
            parsed.kind = kind
        }

        // 主标题
        switch parsed.kind {
        case .pickup:
            parsed.title = value(["code", "title"]) ?? ""
        case .todo:
            parsed.title = value(["headline", "title"]) ?? ""
        case .train:
            parsed.title = value(["train", "title"]) ?? ""
        case .flight:
            parsed.title = value(["flight", "title"]) ?? ""
        }

        // 旧契约没有 kind 参数：按是否有 code 推断取件码
        if parsed.title.isEmpty {
            guard let code = value(["code"]) else { return nil }
            parsed.kind = .pickup
            parsed.title = code
        }
        parsed.title = String(parsed.title.prefix(maxTitle))

        parsed.subtitle = value(["station", "place", "subtitle"]).map { String($0.prefix(maxSubtitle)) }
        parsed.detail = value(["courier", "carrier", "detail"]).map { String($0.prefix(maxDetail)) }
        parsed.from = value(["from"]).map { String($0.prefix(maxSubtitle)) }
        parsed.to = value(["to"]).map { String($0.prefix(maxSubtitle)) }
        parsed.seat = value(["seat"]).map { String($0.prefix(maxDetail)) }
        parsed.car = value(["car"]).map { String($0.prefix(maxDetail)) }
        parsed.gate = value(["gate"]).map { String($0.prefix(maxDetail)) }
        parsed.terminal = value(["terminal", "departureTerminal"]).map { String($0.prefix(maxDetail)) }
        parsed.note = value(["note"]).map { String($0.prefix(maxNote)) }

        if let raw = value(["expiry", "expire", "due", "deadline"]) {
            parsed.due = normalizedDate(raw)
        }
        if let raw = value(["departure"]) {
            parsed.departure = normalizedDate(raw)
        }
        if let raw = value(["arrival"]) {
            parsed.arrival = normalizedDate(raw)
        }

        return parsed
    }

    /// 解析 `done` 动作（按 UUID 标记完成）；失败返回 nil。
    static func parseDoneID(_ url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = components.scheme?.lowercased()
        guard scheme == self.scheme || scheme == legacyScheme else { return nil }
        guard components.host?.lowercased() == "done" else { return nil }
        if let raw = components.queryItems?.first(where: { $0.name.lowercased() == "id" })?.value,
           let uuid = UUID(uuidString: raw) {
            return uuid
        }
        return nil
    }

    /// 解析 `done` 动作（旧契约按取件码标记完成）。
    static func parseDoneCode(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = components.scheme?.lowercased()
        guard scheme == self.scheme || scheme == legacyScheme else { return nil }
        guard components.host?.lowercased() == "done" else { return nil }
        guard let raw = components.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return String(raw.prefix(maxTitle))
    }

    /// 时间归一化：ISO 8601 或 Unix 秒/毫秒时间戳。
    static func normalizedDate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = FloatyDate.date(fromISO: trimmed) {
            return FloatyDate.normalizeISO(date)
        }
        if trimmed.allSatisfy(\.isNumber), trimmed.count >= 10 {
            let secondsText = trimmed.count >= 13 ? String(trimmed.prefix(10)) : trimmed
            if let seconds = TimeInterval(secondsText), seconds > 1_000_000_000 {
                return FloatyDate.normalizeISO(Date(timeIntervalSince1970: seconds))
            }
        }
        return nil
    }

    /// 组装 `floaty://show` URL（App 内测试 / 分享用）。
    static func makeShowURL(kind: FloatyKind,
                            title: String,
                            subtitle: String? = nil,
                            detail: String? = nil,
                            due: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "show"
        var items = [
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "title", value: title)
        ]
        if let subtitle { items.append(URLQueryItem(name: "station", value: subtitle)) }
        if let detail { items.append(URLQueryItem(name: "courier", value: detail)) }
        if let due { items.append(URLQueryItem(name: "expiry", value: due)) }
        components.queryItems = items
        return components.url
    }

    /// 组装 `floaty://done?id=` URL（Widget 侧完成按钮回跳）。
    static func makeDoneURL(id: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "done"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url
    }
}
