import Foundation
import os
import UIKit

/// 自动添加引擎：把短信 / 邮件 / 通知 / 剪贴板里的文本识别成"此刻"内容。
///
/// 对应 Floaty 的自动添加能力：
/// - 短信 SMS（快捷指令 Floaty.SMS 传文本）
/// - 邮件 Mail（快捷指令读取最新一封邮件）
/// - 通知 Notifications（iOS 27+，本工程仅预留接口）
/// - 剪贴板 Scan clipboard on open
///
/// 全部在本机完成（Private, on-device），不联网。
enum AutoAddEngine {

    private static let logger = Logger(subsystem: "com.yourteam.pickupcode", category: "AutoAdd")

    /// 自动添加来源
    enum Source: String, Codable, CaseIterable, Identifiable {
        case sms
        case mail
        case notification
        case clipboard

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .sms: return "短信"
            case .mail: return "邮件"
            case .notification: return "通知"
            case .clipboard: return "剪贴板"
            }
        }

        var symbolName: String {
            switch self {
            case .sms: return "message"
            case .mail: return "envelope"
            case .notification: return "bell.badge"
            case .clipboard: return "doc.on.clipboard"
            }
        }
    }

    /// 识别并入库一条内容。
    /// - Parameters:
    ///   - text: 原始文本
    ///   - source: 来源
    /// - Returns: 命中时返回入库的内容，未命中返回 nil
    @discardableResult
    static func add(text: String, source: Source) -> FloatyItem? {
        let store = FloatyStore.shared

        // 自动添加是本工程的核心能力之一，恒定可用（对应 Floaty Pro 解锁的那一项）
        guard ProAccess.autoAddEnabled else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let result = RecognitionEngine.recognize(
            text: trimmed,
            templates: store.templates,
            builtinPickupEnabled: store.settings.builtinPickupEnabled
        )

        guard let result else {
            logger.debug("来源 \(source.rawValue, privacy: .public) 的内容未匹配任何识别模板")
            return nil
        }

        store.insertOrUpdate(result.item)
        logger.info("已从 \(source.rawValue, privacy: .public) 自动添加：\(result.templateName, privacy: .public) → \(result.item.title, privacy: .public)")

        // 同步到锁屏看板
        refreshBoard()
        return result.item
    }

    /// 批量添加（对应 RecognizeTextListIntent）
    @discardableResult
    static func add(texts: [String], source: Source) -> [FloatyItem] {
        texts.compactMap { add(text: $0, source: source) }
    }

    /// 打开 App 时扫描剪贴板（对应 "Scan clipboard on open"）。
    @discardableResult
    static func scanClipboardIfEnabled() -> FloatyItem? {
        let store = FloatyStore.shared
        guard store.settings.scanClipboardOnOpen else { return nil }
        guard UIPasteboard.general.hasStrings else { return nil }
        guard let text = UIPasteboard.general.string else { return nil }
        return add(text: text, source: .clipboard)
    }

    /// 刷新锁屏看板（内容变化后调用）。
    static func refreshBoard() {
        let store = FloatyStore.shared
        guard store.settings.showOnLockScreen else { return }
        BoardActivityManager.shared.present(items: store.items,
                                            settings: store.settings,
                                            pageIndex: store.boardPageIndex,
                                            focusIndex: store.boardFocusIndex)
    }
}
