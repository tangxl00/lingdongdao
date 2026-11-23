import SwiftUI
import WidgetKit

/// Widget Extension 入口。
/// 本工程提供「此刻」看板 Live Activity（锁屏 + 灵动岛），
/// 桌面上还提供一组静态小组件（当前内容速览）。
@main
struct PickupCodeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BoardLiveActivityWidget()
        FloatyWidget()
    }
}
