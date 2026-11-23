import SwiftUI
import OSLog

@main
struct FloatyApp: App {
    @UIApplicationDelegateAdaptor(FloatyAppDelegate.self) private var appDelegate
    @StateObject private var store = FloatyStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // 回到前台：刷新看板 + 扫描剪贴板
                AutoAddEngine.refreshBoard()
                AutoAddEngine.scanClipboardIfEnabled()
            case .background:
                break
            default:
                break
            }
        }
    }
}
