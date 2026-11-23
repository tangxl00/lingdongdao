import UIKit

/// AppDelegate：处理主屏快捷方式（UIApplicationShortcutItems）。
///
/// 对应 Floaty 的 App Shortcut 深链形态：
/// `com.enjoyio.floaty.compose.{pickup,todo,train,flight}`
/// 本工程对应：
/// `com.yourteam.pickupcode.compose.{pickup,todo,train,flight}`
final class FloatyAppDelegate: NSObject, UIApplicationDelegate {

    /// 收到主屏快捷方式 → 记录待添加类型，主 App 前台时自动弹出对应表单。
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard let kind = Self.kind(for: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        FloatyRepository.savePendingComposeKind(kind)
        completionHandler(true)
    }

    /// 从快捷方式类型解析出内容类型
    static func kind(for type: String) -> FloatyKind? {
        let lowered = type.lowercased()
        if lowered.hasSuffix(".compose.pickup") { return .pickup }
        if lowered.hasSuffix(".compose.todo") { return .todo }
        if lowered.hasSuffix(".compose.train") { return .train }
        if lowered.hasSuffix(".compose.flight") { return .flight }
        return nil
    }
}
