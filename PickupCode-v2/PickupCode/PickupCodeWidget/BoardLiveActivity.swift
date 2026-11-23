import ActivityKit
import SwiftUI
import WidgetKit

/// 锁屏看板 Live Activity（对应 Floaty 的 Board）。
///
/// 静态属性：看板标题 + 类型过滤说明；
/// 动态状态：当前页卡片、页码、聚焦项、倒计时。
struct BoardLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FloatyAttributes.self) { context in
            BoardLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BoardDynamicIslandLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    BoardDynamicIslandCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BoardDynamicIslandTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BoardDynamicIslandBottomView(context: context)
                }
            } compactLeading: {
                BoardCompactLeadingView(context: context)
            } compactTrailing: {
                BoardCompactTrailingView(context: context)
            } minimal: {
                BoardMinimalView(context: context)
            }
        }
    }
}

// MARK: - 锁屏看板视图

/// 锁屏 / 横幅布局：多卡片列表 + 聚焦卡片。
struct BoardLockScreenView: View {
    let context: ActivityViewContext<FloatyAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(context.attributes.title, systemImage: "lock.rectangle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(context.attributes.filterDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(context.state.cards) { card in
                BoardCardRow(card: card, isFocused: card.id == focusedCardID)
            }

            if let focused = focusedCard, !focused.isCompleted {
                if let url = URL(string: "floaty://done?id=\(focused.id.uuidString)") {
                    Link(destination: url) {
                        Label("完成", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.green.opacity(0.3), in: Capsule())
                    }
                }
            }

            if context.state.pageCount > 1 {
                Text("第 \(context.state.pageIndex + 1) / \(context.state.pageCount) 页")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.55))
    }

    private var focusedCardID: UUID? {
        let index = context.state.focusIndex
        guard index >= 0, index < context.state.cards.count else { return nil }
        return context.state.cards[index].id
    }

    private var focusedCard: BoardCard? {
        let index = context.state.focusIndex
        guard index >= 0, index < context.state.cards.count else { return nil }
        return context.state.cards[index]
    }
}

/// 看板中的一行卡片
struct BoardCardRow: View {
    let card: BoardCard
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: card.kind.symbolName)
                .foregroundStyle(card.isCompleted ? Color.green : (card.isExpiringSoon ? Color.orange : Color.accentColor))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                    if card.checklistTotal > 0 {
                        Text("\(card.checklistDone)/\(card.checklistTotal)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if card.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(card.dueText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(card.isExpiringSoon ? .orange : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(6)
        .background(isFocused ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 灵动岛

/// leading：看板标题 + 过滤说明
struct BoardDynamicIslandLeadingView: View {
    let context: ActivityViewContext<FloatyAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(context.attributes.title, systemImage: "lock.rectangle")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(context.attributes.filterDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: 110, alignment: .leading)
    }
}

/// center：聚焦卡片主标题
struct BoardDynamicIslandCenterView: View {
    let context: ActivityViewContext<FloatyAttributes>

    var body: some View {
        if let card = focusedCard {
            Text(card.title)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(card.isExpiringSoon && !card.isCompleted ? Color.orange : Color.white)
                .frame(maxWidth: 130)
        }
    }

    private var focusedCard: BoardCard? {
        let index = context.state.focusIndex
        guard index >= 0, index < context.state.cards.count else { return nil }
        return context.state.cards[index]
    }
}

/// trailing：剩余时间
struct BoardDynamicIslandTrailingView: View {
    let context: ActivityViewContext<FloatyAttributes>

    var body: some View {
        if context.state.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "timer").font(.caption)
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

/// bottom：页码 + 备注 + 完成按钮
struct BoardDynamicIslandBottomView: View {
    let context: ActivityViewContext<FloatyAttributes>

    var body: some View {
        HStack(spacing: 12) {
            if context.state.isCompleted {
                Label("已完成", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            } else {
                if let note = context.state.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if context.state.pageCount > 1 {
                    Text("\(context.state.pageIndex + 1)/\(context.state.pageCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// compact leading：聚焦卡片类型图标
struct BoardCompactLeadingView: View {
    let context: ActivityViewContext<FloatyAttributes>

    var body: some View {
        let index = context.state.focusIndex
        if index >= 0, index < context.state.cards.count {
            Image(systemName: context.state.cards[index].kind.symbolName)
                .foregroundStyle(context.state.isExpiringSoon && !context.state.isCompleted ? .orange : .white)
        }
    }
}

/// compact trailing：剩余时间缩写
struct BoardCompactTrailingView: View {
    let context: ActivityViewContext<FloatyAttributes>

    var body: some View {
        if context.state.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Text(compactText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(context.state.isExpiringSoon ? .orange : .white)
                .frame(maxWidth: 70)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var compactText: String {
        let text = context.state.timeRemainingText
        if text.contains("小时") {
            let parts = text.split(separator: " ")
            if parts.count >= 2 { return "\(parts[0])h" }
        }
        return text.replacingOccurrences(of: "剩余 ", with: "")
            .replacingOccurrences(of: " 分钟", with: "m")
            .replacingOccurrences(of: " 分", with: "m")
    }
}

/// minimal：状态点
struct BoardMinimalView: View {
    let context: ActivityViewContext<FloatyAttributes>

    var body: some View {
        if context.state.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "lock.rectangle")
                .foregroundStyle(context.state.isExpiringSoon ? .orange : .white)
        }
    }
}
