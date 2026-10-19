import SwiftUI
import WidgetKit

/// Widget Extension 入口。
/// 本工程当前只提供 Live Activity（灵动岛 + 锁屏），暂无桌面小组件需求；
/// 保留 WidgetBundle 结构便于后续扩展。
@main
struct PickupCodeWidgetBundle: WidgetBundle {
    var body: some Widget {
        PickupCodeLiveActivityWidget()
    }
}
