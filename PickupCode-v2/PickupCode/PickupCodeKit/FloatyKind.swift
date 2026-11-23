import Foundation

/// 卡片类型（对应 Floaty 的 ComposeKind）：取件码 / 待办 / 火车票 / 机票。
enum FloatyKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case pickup
    case todo
    case train
    case flight

    var id: String { rawValue }

    /// 中文名称
    var displayName: String {
        switch self {
        case .pickup: return "取件码"
        case .todo: return "待办"
        case .train: return "火车票"
        case .flight: return "机票"
        }
    }

    /// SF Symbol（对应 Floaty 内置图标）
    var symbolName: String {
        switch self {
        case .pickup: return "shippingbox"
        case .todo: return "checklist"
        case .train: return "train.side.front.car"
        case .flight: return "airplane"
        }
    }

    /// 看板排序权重
    var sortWeight: Int {
        switch self {
        case .pickup: return 0
        case .train: return 1
        case .flight: return 2
        case .todo: return 3
        }
    }
}

/// 锁屏看板的类型过滤方式（对应 Floaty 的 BoardKindFilter）。
enum BoardKindFilter: String, Codable, CaseIterable, Identifiable, Hashable {
    case off
    case only
    case except

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "不显示"
        case .only: return "仅显示所选类型"
        case .except: return "排除所选类型"
        }
    }
}
