import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - 灵动岛扩展（Expanded）布局

/// leading：驿站名 + 快递公司
struct DynamicIslandLeadingView: View {
    let context: ActivityViewContext<PickupCodeAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(context.attributes.station, systemImage: "shippingbox")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let courier = context.attributes.courier, !courier.isEmpty {
                Text(courier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 110, alignment: .leading)
    }
}

/// center：取件码大号字
struct DynamicIslandCenterView: View {
    let context: ActivityViewContext<PickupCodeAttributes>

    var body: some View {
        Text(context.attributes.code)
            .font(.system(.title2, design: .monospaced).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(context.state.isExpiringSoon && !context.state.isCompleted ? Color.orange : Color.white)
            .frame(maxWidth: 130)
    }
}

/// trailing：剩余时间（isCompleted 时显示对勾）
struct DynamicIslandTrailingView: View {
    let context: ActivityViewContext<PickupCodeAttributes>

    var body: some View {
        if context.state.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "timer")
                    .font(.caption)
                Text(context.state.timeRemainingText)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(context.state.isExpiringSoon ? .orange : .secondary)
            }
            .frame(maxWidth: 90, alignment: .trailing)
        }
    }
}

/// bottom："已取件"按钮（深链回主 App 结束活动）
struct DynamicIslandBottomView: View {
    let context: ActivityViewContext<PickupCodeAttributes>

    var body: some View {
        HStack(spacing: 12) {
            if context.state.isCompleted {
                Label("已取件，可轻点关闭", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            } else {
                if let note = noteText {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                doneButton
            }
        }
    }

    private var noteText: String? {
        // expiry 已过期时给一行提示（Attributes 不含 note，避免动态区超载）
        guard !context.state.isCompleted else { return nil }
        guard let expiry = context.attributes.expiry,
              let date = PickupCodeDate.date(fromISO: expiry),
              date <= Date() else { return nil }
        return "已超过建议取件时间"
    }

    private var doneButton: some View {
        Group {
            if let url = URL(string: "pickupcode://done?code=\(encodedCode)") {
                Link(destination: url) {
                    Label("已取件", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.25), in: Capsule())
                }
                .simultaneousGesture(TapGesture().onEnded {
                    // 同时写 App Group 完成标记：付费账号配置 App Group 后，
                    // 主 App 即使未被唤起，下次前台激活对账时也能识别（免费账号回退为深链唤起主 App 更新）。
                    CompletedMarker.markCompleted(code: context.attributes.code)
                })
            }
        }
    }

    private var encodedCode: String {
        context.attributes.code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? context.attributes.code
    }
}

// MARK: - 灵动岛紧凑（Compact）与最小（Minimal）布局

/// compact leading：取件码（紧凑态最重要的是码本身）
struct CompactLeadingView: View {
    let context: ActivityViewContext<PickupCodeAttributes>

    var body: some View {
        Text(context.attributes.code)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(context.state.isExpiringSoon && !context.state.isCompleted ? .orange : .white)
    }
}

/// compact trailing：剩余时间缩写（整块可点，等效"已取件"）
struct CompactTrailingView: View {
    let context: ActivityViewContext<PickupCodeAttributes>

    var body: some View {
        if context.state.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Text(compactTimeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(context.state.isExpiringSoon ? .orange : .white)
                .frame(maxWidth: 70)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// 紧凑态剩余时间缩写："2h5m" / "38m" / "已到期"
    private var compactTimeText: String {
        guard let expiry = context.attributes.expiry,
              let date = PickupCodeDate.date(fromISO: expiry) else {
            return "尽快"
        }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "已到期" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }
}

/// minimal：取件码首几位 + 状态色点
struct MinimalView: View {
    let context: ActivityViewContext<PickupCodeAttributes>

    var body: some View {
        if context.state.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Text(String(context.attributes.code.prefix(4)))
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(context.state.isExpiringSoon ? .orange : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - App Group 完成标记（Widget 进程侧）

/// 在 Widget 进程写入 App Group "已取件"标记。
/// - 付费账号（已配置 App Group entitlement）：主 App 下次前台激活对账时读取；
/// - 免费账号：suiteName 初始化失败/无权限时静默降级，实际状态更新依赖
///   "已取件"按钮深链唤起主 App（pickupcode://done?code=...）。
enum CompletedMarker {
    @discardableResult
    static func markCompleted(code: String) -> Bool {
        guard let suite = UserDefaults(suiteName: PickupCodeStorage.appGroupID) else { return false }
        suite.set(Date(), forKey: PickupCodeStorage.completedMarkerPrefix + code)
        return true
    }
}
