import ActivityKit
import SwiftUI
import WidgetKit

/// 取件码 Live Activity：灵动岛 + 锁屏实时活动。
/// 布局实现见 DynamicIslandViews / LockScreenView。
struct PickupCodeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupCodeAttributes.self) { context in
            // 锁屏 / 横幅（通知下拉）布局
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DynamicIslandLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    DynamicIslandCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DynamicIslandTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandBottomView(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
        }
    }
}
