import Foundation

/// 识别引擎：把一段文本（短信 / 邮件 / 通知 / 剪贴板）解析成一条"此刻"内容。
///
/// 全部在本机完成，不联网、不调用云端模型（对应 Floaty 的 "Private, on-device"）。
enum RecognitionEngine {

    /// 识别结果
    struct Result {
        var item: FloatyItem
        /// 命中的模板名
        var templateName: String
    }

    /// 用给定模板集合识别文本。
    ///
    /// - Parameters:
    ///   - text: 待识别文本
    ///   - templates: 模板集合（内置 + 用户自定义）
    ///   - builtinPickupEnabled: 内置取件识别是否开启（对应 Floaty 的 "Built-in pickup recognition"）
    ///   - now: 参考时间
    /// - returns: 首个命中的结果；未命中返回 nil
    static func recognize(text: String,
                          templates: [RecognitionTemplate],
                          builtinPickupEnabled: Bool = true,
                          now: Date = Date()) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let ordered = orderedTemplates(templates, builtinPickupEnabled: builtinPickupEnabled)

        // 逐类型尝试：先整体匹配，命中即返回
        for kind in FloatyKind.allCases {
            for template in ordered where template.kind == kind {
                if let item = match(template: template, in: trimmed, now: now) {
                    return Result(item: item, templateName: template.name)
                }
            }
        }
        return nil
    }

    /// 批量识别（对应 Floaty 的 RecognizeTextListIntent）。
    static func recognizeList(texts: [String],
                              templates: [RecognitionTemplate],
                              builtinPickupEnabled: Bool = true,
                              now: Date = Date()) -> [Result] {
        texts.compactMap { recognize(text: $0, templates: templates, builtinPickupEnabled: builtinPickupEnabled, now: now) }
    }

    /// 模板排序：内置在前（按类型），自定义在后；保证结果稳定。
    private static func orderedTemplates(_ templates: [RecognitionTemplate],
                                         builtinPickupEnabled: Bool) -> [RecognitionTemplate] {
        templates
            .filter { template in
                if template.isBuiltin && template.kind == .pickup {
                    return builtinPickupEnabled
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.isBuiltin != rhs.isBuiltin { return lhs.isBuiltin }
                if lhs.kind != rhs.kind { return lhs.kind.sortWeight < rhs.kind.sortWeight }
                return lhs.name < rhs.name
            }
    }

    /// 单模板匹配 → 生成 FloatyItem
    private static func match(template: RecognitionTemplate, in text: String, now: Date) -> FloatyItem? {
        guard let regex = template.compiled() else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let first = regex.firstMatch(in: text, options: [], range: range) else { return nil }

        let groups = captureGroups(regex: regex, match: first, in: ns)

        // 各类型的主标识
        var title: String?
        var subtitle: String?
        var from: String?
        var to: String?
        var departure: String?
        var arrival: String?
        var due: String?
        var seat: String?
        var car: String?
        var gate: String?
        var terminal: String?
        var note: String?

        switch template.kind {
        case .pickup:
            guard let code = groups["code"], !code.isEmpty else { return nil }
            title = code
            subtitle = groups["place"]
            due = groups["due"] ?? groups["expiry"]
        case .train:
            guard let train = groups["train"], !train.isEmpty else { return nil }
            title = train
            from = groups["from"]
            to = groups["to"]
            departure = groups["departure"]
            arrival = groups["arrival"]
            seat = groups["seat"]
            car = groups["car"]
            gate = groups["gate"]
        case .flight:
            guard let flight = groups["flight"], !flight.isEmpty else { return nil }
            title = flight
            from = groups["from"]
            to = groups["to"]
            departure = groups["departure"]
            arrival = groups["arrival"]
            seat = groups["seat"]
            gate = groups["gate"]
            terminal = groups["departureTerminal"]
        case .todo:
            guard let headline = groups["headline"], !headline.isEmpty else { return nil }
            title = headline
            note = groups["note"]
            due = groups["due"] ?? groups["deadline"]
        }

        guard let resolvedTitle = title else { return nil }

        // 时间归一化
        if let raw = departure, !raw.isEmpty {
            if let parsed = FloatyDate.parseDeparture(raw, now: now) {
                departure = FloatyDate.normalizeISO(parsed)
            }
        }
        if let raw = arrival, !raw.isEmpty {
            if let parsed = FloatyDate.parseDeparture(raw, now: now) {
                arrival = FloatyDate.normalizeISO(parsed)
            }
        }
        if let raw = due, !raw.isEmpty {
            if FloatyDate.date(fromISO: raw) == nil, let parsed = FloatyDate.parseDeparture(raw, now: now) {
                due = FloatyDate.normalizeISO(parsed)
            }
        }

        // 补充字段：主模板没抓到时，从同一段文本里再扫一遍补充模板
        if template.kind == .train || template.kind == .flight {
            if let detailTemplate = BuiltinTemplates.supplementary(for: template.kind),
               let detailRegex = detailTemplate.compiled(),
               let extra = detailRegex.firstMatch(in: text, options: [], range: range) {
                let extraGroups = captureGroups(regex: detailRegex, match: extra, in: ns)
                if seat == nil { seat = extraGroups["seat"] }
                if car == nil { car = extraGroups["car"] }
                if gate == nil { gate = extraGroups["gate"] }
                if terminal == nil { terminal = extraGroups["departureTerminal"] }
            }
        }

        return FloatyItem(
            kind: template.kind,
            title: resolvedTitle,
            subtitle: subtitle,
            from: from,
            to: to,
            departure: departure,
            arrival: arrival,
            due: due,
            seat: seat,
            car: car,
            gate: gate,
            terminal: terminal,
            note: note,
            createdAt: now
        )
    }

    /// 提取所有命名捕获组
    private static func captureGroups(regex: NSRegularExpression,
                                      match: NSTextCheckingResult,
                                      in ns: NSString) -> [String: String] {
        var result: [String: String] = [:]
        let names = captureNames(regex: regex)
        for index in 0..<match.numberOfRanges {
            let rangeIndex = index + 1
            guard rangeIndex < names.count else { continue }
            let name = names[rangeIndex]
            guard !name.isEmpty else { continue }
            let range = match.range(at: rangeIndex)
            guard range.location != NSNotFound, range.length > 0 else { continue }
            result[name] = ns.substring(with: range)
        }
        return result
    }

    /// 读取正则中的捕获组名（按 group 序号顺序，未命名组为空串）。
    ///
    /// 解析要点：
    /// - 跳过转义字符 `\(` `\)`
    /// - 跳过字符类 `[...]` 内的括号
    /// - 识别命名组 `(?<name>` `(?P<name>` `(?'name'`
    /// - 忽略非捕获组与断言 `(?: (?= (?! (?<= (?<! (?i) ...`
    private static func captureNames(regex: NSRegularExpression) -> [String] {
        let pattern = regex.pattern
        var names: [String] = [""]
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let ch = pattern[index]

            if ch == "\\" {
                // 转义：跳过当前字符与被转义字符
                index = pattern.index(after: index)
                if index < pattern.endIndex {
                    index = pattern.index(after: index)
                }
                continue
            }

            if ch == "[" {
                // 字符类：跳到对应的 ']'
                index = pattern.index(after: index)
                if index < pattern.endIndex, pattern[index] == "^" {
                    index = pattern.index(after: index)
                }
                if index < pattern.endIndex, pattern[index] == "]" {
                    index = pattern.index(after: index)
                }
                while index < pattern.endIndex, pattern[index] != "]" {
                    if pattern[index] == "\\" {
                        index = pattern.index(after: index)
                    }
                    if index < pattern.endIndex {
                        index = pattern.index(after: index)
                    }
                }
                if index < pattern.endIndex {
                    index = pattern.index(after: index)
                }
                continue
            }

            if ch == "(" {
                if let (name, nextIndex) = parseGroupHeader(pattern, from: index) {
                    names.append(name)
                    index = nextIndex
                    continue
                }
                // 非捕获 / 断言组：本身不占捕获序号，只跳过 "("，
                // 其内部仍可能出现嵌套的捕获组，需继续扫描
                index = pattern.index(after: index)
                continue
            }

            index = pattern.index(after: index)
        }

        return names
    }

    /// 解析 `(` 开头的组头，返回（组名，是否为捕获组，下一位置）。
    private static func parseGroupHeader(_ pattern: String, from start: String.Index) -> (String, String.Index)? {
        let open = pattern.index(after: start)
        guard open < pattern.endIndex else { return nil }

        // 普通捕获组
        if pattern[open] != "?" {
            return ("", open)
        }

        var cursor = pattern.index(after: open)
        guard cursor < pattern.endIndex else { return nil }

        // (?:  (?=  (?!  (?<=  (?<!  (?i) 等 → 非捕获
        if pattern[cursor] == ":" {
            return nil
        }
        if pattern[cursor] == "=" || pattern[cursor] == "!" {
            return nil
        }
        if pattern[cursor] == "<" {
            let after = pattern.index(after: cursor)
            if after < pattern.endIndex, pattern[after] == "=" || pattern[after] == "!" {
                return nil
            }
        }
        if pattern[cursor] == "P" {
            let after = pattern.index(after: cursor)
            if after < pattern.endIndex, pattern[after] == "<" {
                return parseNamedGroup(pattern, nameStart: pattern.index(after: after), terminator: ">")
            }
            return nil
        }
        if pattern[cursor] == "'" {
            return parseNamedGroup(pattern, nameStart: pattern.index(after: cursor), terminator: "'")
        }
        if pattern[cursor] == "<" {
            return parseNamedGroup(pattern, nameStart: pattern.index(after: cursor), terminator: ">")
        }
        // 其余 (?...) 内联修饰组：(?(id)name)、(?i) 等 → 视为非捕获
        return nil
    }

    /// 解析命名组 `(?<name>` / `(?P<name>` / `(?'name'`
    private static func parseNamedGroup(_ pattern: String, nameStart: String.Index, terminator: Character) -> (String, String.Index)? {
        var cursor = nameStart
        var name = ""
        while cursor < pattern.endIndex, pattern[cursor] != terminator {
            name.append(pattern[cursor])
            cursor = pattern.index(after: cursor)
        }
        guard cursor < pattern.endIndex else { return nil }
        // 跳过 '>' 之后的一个字符（分组开始）
        cursor = pattern.index(after: cursor)
        return (name, cursor)
    }
}
