import SwiftUI
import WidgetKit

/// 桌面小组件：把「此刻」的内容（取件码 / 火车票 / 机票 / 待办）放到主屏。
///
/// 数据来自共享 UserDefaults（配置了 App Group 时与主 App 互通）。
struct FloatyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FloatyWidget", provider: FloatyTimelineProvider()) { entry in
            FloatyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("此刻")
        .description("在主屏查看取件码、火车票、机票与待办。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// 时间线提供器
struct FloatyTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> FloatyEntry {
        FloatyEntry(date: Date(), items: FloatyRepository.loadItems())
    }

    func getSnapshot(in context: Context, completion: @escaping (FloatyEntry) -> Void) {
        completion(FloatyEntry(date: Date(), items: FloatyRepository.loadItems()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FloatyEntry>) -> Void) {
        let entry = FloatyEntry(date: Date(), items: FloatyRepository.loadItems())
        // 每 15 分钟刷新一次倒计时
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// 时间线条目
struct FloatyEntry: TimelineEntry {
    let date: Date
    let items: [FloatyItem]
}

/// 小组件视图
struct FloatyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FloatyEntry

    private var activeItems: [FloatyItem] {
        entry.items.filter { !$0.isCompleted && !$0.isExpired }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("此刻", systemImage: "lock.rectangle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(activeItems.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if activeItems.isEmpty {
                Spacer()
                Text("暂无内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(activeItems.prefix(maxItems)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.kind.symbolName)
                            .font(.caption2)
                            .foregroundStyle(.accent)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold).monospaced())
                                .lineLimit(1)
                            if let subtitle = item.displaySubtitle {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                if family == .systemSmall, activeItems.count > maxItems {
                    Text("还有 \(activeItems.count - maxItems) 条")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var maxItems: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 4
        default: return 8
        }
    }
}
