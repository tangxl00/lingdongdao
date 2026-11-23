import Foundation

/// 识别模板：一条正则 + 命名捕获组 → 一条"此刻"内容。
///
/// 命名捕获组对应 Floaty 支持的字段：
/// `code` `place` `train` `flight` `from` `to` `departure` `arrival`
/// `departureTerminal` `arrivalTerminal` `seat` `car` `gate` `headline` `note`
/// `due`（取件截止 / 待办截止）
struct RecognitionTemplate: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: FloatyKind
    var name: String
    /// 正则表达式（必须含命名捕获组）
    var regex: String
    /// 内置模板不可删除
    var isBuiltin: Bool
    /// 示例文本
    var sample: String

    init(id: UUID = UUID(),
         kind: FloatyKind,
         name: String,
         regex: String,
         isBuiltin: Bool = false,
         sample: String = "") {
        self.id = id
        self.kind = kind
        self.name = name
        self.regex = regex
        self.isBuiltin = isBuiltin
        self.sample = sample
    }

    /// 编译后的正则（无效时返回 nil）
    func compiled() -> NSRegularExpression? {
        try? NSRegularExpression(pattern: regex, options: [.caseInsensitive])
    }
}

/// 内置识别模板（对应 Floaty 的内置样例正则）。
///
/// 内置模板使用固定 UUID，保证跨启动可持久化（用户改了内置模板也不会被覆盖回默认）。
enum BuiltinTemplates {

    /// 取件码（英文样例）
    static let pickupEN = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000001")!,
        kind: .pickup,
        name: "取件码（英文）",
        regex: #"at (?<place>.+?)\. Pickup code: (?<code>[A-Za-z0-9\-]+)"#,
        isBuiltin: true,
        sample: "Your parcel is at Front Desk. Pickup code: A-8-9527."
    )

    /// 取件码（中文短信优化版）
    static let pickupZH = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000002")!,
        kind: .pickup,
        name: "取件码（中文）",
        regex: #"已到(?<place>.+?)，取件码[:：\s]*(?<code>[A-Za-z0-9\-]+)"#,
        isBuiltin: true,
        sample: "您的包裹已到丰巢，取件码：A-8-9527，请及时取走"
    )

    /// 取件码（通用：取件码[:：]xxx）
    static let pickupGeneric = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000003")!,
        kind: .pickup,
        name: "取件码（通用）",
        regex: #"取件码[:：]?\s*(?<code>[A-Za-z0-9\-]+)"#,
        isBuiltin: true,
        sample: "取件码：886677"
    )

    /// 取件码（含截止时间）
    static let pickupWithDeadline = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000004")!,
        kind: .pickup,
        name: "取件码（含截止时间）",
        regex: #"取件码[:：]?\s*(?<code>[A-Za-z0-9\-]+).*?(?<due>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?)"#,
        isBuiltin: true,
        sample: "取件码：886677，请于 2026-10-24 18:00 前取走"
    )

    /// 火车票
    static let train = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000005")!,
        kind: .train,
        name: "火车票",
        regex: #"Train (?<train>[A-Z]\d+), departs (?<departure>.+?), (?<from>.+?)\s*→\s*(?<to>.+?),"#,
        isBuiltin: true,
        sample: "Train G9527, departs Oct 24 14:30, Beijing South → Shanghai Hongqiao, car 5 seat 12A, ticket gate B12."
    )

    /// 火车票（中文）
    static let trainZH = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000006")!,
        kind: .train,
        name: "火车票（中文）",
        regex: #"(?<train>[GDCZTKY]\d{1,4})次?[,，]?\s*(?<from>.+?)[-—→至到](?<to>.+?)[,，].*?(?<departure>\d{1,2}月\d{1,2}日\d{1,2}:\d{2}|\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2})"#,
        isBuiltin: true,
        sample: "G9527次，北京南-上海虹桥，10月24日14:30 开，05车12A号，检票口B12"
    )

    /// 机票
    static let flight = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000007")!,
        kind: .flight,
        name: "机票",
        regex: #"Flight (?<flight>[A-Z0-9]+), departs (?<departure>.+?), (?<from>.+?)\s+(?<departureTerminal>T\d+)\s*→\s*(?<to>.+?)\s+(?<arrivalTerminal>T\d+),"#,
        isBuiltin: true,
        sample: "Flight CA9527, departs Oct 24 08:15, PEK T3 → PVG T2, seat 32A, gate C12."
    )

    /// 机票（中文）
    static let flightZH = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000008")!,
        kind: .flight,
        name: "机票（中文）",
        regex: #"(?<flight>[A-Z]{2}\d{3,4}).*?(?<from>[A-Z]{3})\s*(?<departureTerminal>T\d)?.*?(?<to>[A-Z]{3})\s*(?<arrivalTerminal>T\d)?.*?(?<departure>\d{1,2}月\d{1,2}日\d{1,2}:\d{2}|\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2})"#,
        isBuiltin: true,
        sample: "CA9527，PEK T3 飞 PVG T2，10月24日08:15 起飞，座位32A，登机口C12"
    )

    /// 待办
    static let todo = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-000000000009")!,
        kind: .todo,
        name: "待办",
        regex: #"Remember to (?<headline>.+?)\. Note: (?<note>.+)"#,
        isBuiltin: true,
        sample: "Remember to pick up the package this afternoon. Note: at the door"
    )

    /// 待办（中文）
    static let todoZH = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-00000000000A")!,
        kind: .todo,
        name: "待办（中文）",
        regex: #"记得(?<headline>.+?)[，,。]?\s*备注[:：]?\s*(?<note>.+)"#,
        isBuiltin: true,
        sample: "记得下午去取快递，备注：放在门口"
    )

    /// 火车票补充字段（车厢 / 座位 / 检票口）
    static let trainDetails = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-00000000000B")!,
        kind: .train,
        name: "火车票（车厢座位）",
        regex: #"car (?<car>\d+) seat (?<seat>[A-Za-z0-9]+)"#,
        isBuiltin: true,
        sample: "car 5 seat 12A, ticket gate B12."
    )

    /// 机票补充字段（座位 / 登机口）
    static let flightDetails = RecognitionTemplate(
        id: UUID(uuidString: "0F1A0001-0000-4000-8000-00000000000C")!,
        kind: .flight,
        name: "机票（座位登机口）",
        regex: #"seat (?<seat>[A-Za-z0-9]+), gate (?<gate>[A-Za-z0-9]+)"#,
        isBuiltin: true,
        sample: "seat 32A, gate C12."
    )

    /// 全部内置模板
    static let all: [RecognitionTemplate] = [
        pickupEN, pickupZH, pickupGeneric, pickupWithDeadline,
        train, trainZH, trainDetails,
        flight, flightZH, flightDetails,
        todo, todoZH
    ]

    /// 内置模板 ID 集合（用于迁移时去重）
    static var builtinIDs: Set<UUID> { Set(all.map(\.id)) }

    /// 取某类型的补充字段模板（座位 / 车厢 / 检票口）
    static func supplementary(for kind: FloatyKind) -> RecognitionTemplate? {
        switch kind {
        case .train: return trainDetails
        case .flight: return flightDetails
        default: return nil
        }
    }
}
