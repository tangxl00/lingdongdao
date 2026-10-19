import SwiftUI
import OSLog

@main
struct PickupCodeApp: App {
    @StateObject private var history = HistoryStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(history)
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            // 回到前台：与系统 Live Activity 对账 + 刷新倒计时
            HistoryStore.shared.reconcileWithSystem()
        }
    }
}
