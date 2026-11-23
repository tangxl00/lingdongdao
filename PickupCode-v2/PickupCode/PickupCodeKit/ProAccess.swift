import Foundation

/// 付费能力开关。
///
/// 本工程为完全开源、永久免费实现：**没有购买流程、没有订阅、没有付费墙**。
///
/// 逆向 Floaty（com.enjoyio.floaty 1.1.0）确认其付费模型为 RevenueCat：
/// `PaywallPresenter` / `presentPaywallIfNeeded` / `requiredEntitlementIdentifier` /
/// `CustomerInfo.entitlements` / `hasEntitlement` / `activeEntitlements`，
/// 付费文案 "Upgrade to Floaty Pro to add items automatically."
/// —— 即 Pro 只解锁「短信/邮件/通知自动添加」，手动添加与锁屏显示免费。
///
/// 本实现直接用本地常量替代 entitlement 校验：所有功能恒定可用。
enum ProAccess {

    /// 是否为 Pro：恒为 true（本工程无付费墙）。
    static let isPro: Bool = true

    /// 是否解锁「短信 / 邮件 / 通知自动添加」：恒为 true。
    static let autoAddEnabled: Bool = true

    /// 付费墙相关 UI 一律不展示。
    static let showsPaywall: Bool = false

    /// 供 UI 展示的版本说明文案。
    static let proDescription: String {
        "全部功能永久免费开源 · 无订阅 · 无内购"
    }
}
