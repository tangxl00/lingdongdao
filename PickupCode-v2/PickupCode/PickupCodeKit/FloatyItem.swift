import Foundation

/// 待办子项（清单行）。
struct ChecklistLine: Codable, Identifiable, Hashable {
    var id: UUID
    var text: String
    var isDone: Bool

    init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

/// 一条"此刻"内容：取件码 / 待办 / 火车票 / 机票。
///
/// 字段对应 Floaty 的四种数据类型：
/// - 取件码：title=码，subtitle=取件地点，detail=快递公司，due=取件截止时间
/// - 火车票：title=车次，from/to=起止，departure=出发，car/seat/gate=车厢座位检票口
/// - 机票：title=航班号，from/to=起止，departure/arrival=起降时间，terminal=航站楼
/// - 待办：title=标题，checklist=子项，due=截止时间
struct FloatyItem: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: FloatyKind
    /// 主标题：取件码 / 车次 / 航班号 / 待办标题
    var title: String
    /// 副标题：取件地点 / 路线 / 备注
    var subtitle: String?
    /// 附加信息：快递公司等
    var detail: String?
    var from: String?
    var to: String?
    /// 出发时间（ISO 8601）
    var departure: String?
    /// 到达时间（ISO 8601）
    var arrival: String?
    /// 截止时间（ISO 8601）：取件截止 / 待办截止
    var due: String?
    var seat: String?
    var car: String?
    var gate: String?
    /// 航站楼
    var terminal: String?
    var note: String?
    var checklist: [ChecklistLine]
    var createdAt: Date
    var isCompleted: Bool
    /// 已超时（Live Activity 超过系统 8 小时上限自动消失，未被用户确认）
    var isExpired: Bool
    /// 是否成功启动过 Live Activity（对账时用于区分"从未启动"与"已结束"）
    var didStartActivity: Bool
    /// 每日取件提醒
    var dailyReminder: Bool

    init(id: UUID = UUID(),
         kind: FloatyKind,
         title: String,
         subtitle: String? = nil,
         detail: String? = nil,
         from: String? = nil,
         to: String? = nil,
         departure: String? = nil,
         arrival: String? = nil,
         due: String? = nil,
         seat: String? = nil,
         car: String? = nil,
         gate: String? = nil,
         terminal: String? = nil,
         note: String? = nil,
         checklist: [ChecklistLine] = [],
         createdAt: Date = Date(),
         isCompleted: Bool = false,
         isExpired: Bool = false,
         didStartActivity: Bool = false,
         dailyReminder: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.from = from
        self.to = to
        self.departure = departure
        self.arrival = arrival
        self.due = due
        self.seat = seat
        self.car = car
        self.gate = gate
        self.terminal = terminal
        self.note = note
        self.checklist = checklist
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.isExpired = isExpired
        self.didStartActivity = didStartActivity
        self.dailyReminder = dailyReminder
    }

    var dueDate: Date? { due.flatMap { FloatyDate.date(fromISO: $0) } }
    var departureDate: Date? { departure.flatMap { FloatyDate.date(fromISO: $0) } }
    var arrivalDate: Date? { arrival.flatMap { FloatyDate.date(fromISO: $0) } }

    /// 倒计时参考时间：取件截止 / 出发时间 / 待办截止
    var referenceDate: Date? {
        switch kind {
        case .pickup, .todo:
            return dueDate
        case .train, .flight:
            return departureDate
        }
    }

    /// 状态显示文案
    var statusText: String {
        if isCompleted { return "已完成" }
        if isExpired { return "已超时" }
        switch kind {
        case .pickup: return "待取件"
        case .todo: return "待办"
        case .train: return "待出发"
        case .flight: return "待起飞"
        }
    }

    var checklistDone: Int { checklist.filter(\.isDone).count }
    var checklistTotal: Int { checklist.count }

    /// 详情行（车厢 / 座位 / 检票口 / 航站楼 / 快递公司）
    var detailText: String? {
        var parts: [String] = []
        if let car, !car.isEmpty { parts.append("\(car)车") }
        if let seat, !seat.isEmpty { parts.append("\(seat)座") }
        if let gate, !gate.isEmpty { parts.append("检票口 \(gate)") }
        if let terminal, !terminal.isEmpty { parts.append(terminal) }
        if let detail, !detail.isEmpty { parts.append(detail) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 路线文案（起 → 止）
    var routeText: String? {
        let f = (from ?? "").trimmingCharacters(in: .whitespaces)
        let t = (to ?? "").trimmingCharacters(in: .whitespaces)
        if !f.isEmpty && !t.isEmpty { return "\(f) → \(t)" }
        if !f.isEmpty { return f }
        if !t.isEmpty { return t }
        return nil
    }

    /// 副标题兜底：优先路线，其次地点
    var displaySubtitle: String? {
        if let route = routeText { return route }
        if let subtitle, !subtitle.isEmpty { return subtitle }
        return nil
    }
}
