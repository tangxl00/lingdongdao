import Foundation
import os
import UserNotifications

/// 通知提醒调度：待办截止提醒 / 每日取件提醒。
enum ReminderScheduler {

    private static let logger = Logger(subsystem: "com.yourteam.pickupcode", category: "Reminder")

    /// 待办截止提醒的请求 ID 前缀
    static let deadlinePrefix = "floaty.deadline."
    /// 每日取件提醒的请求 ID
    static let dailyReminderID = "floaty.daily.reminder"

    /// 请求通知权限
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("通知授权失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 为一条待办安排截止提醒
    static func scheduleDeadlineReminder(for item: FloatyItem) {
        guard item.kind == .todo else { return }
        guard let due = item.dueDate, due > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "待办到期"
        content.body = item.title
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: deadlinePrefix + item.id.uuidString,
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("截止提醒注册失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 取消某条待办的截止提醒
    static func cancelDeadlineReminder(itemID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [deadlinePrefix + itemID.uuidString])
    }

    /// 设置每日取件提醒（对应 "Daily pick-up reminder"）。
    static func scheduleDailyReminder(enabled: Bool, time: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderID])

        guard enabled, let date = FloatyDate.parseTimeOnly(time) else { return }

        let content = UNMutableNotificationContent()
        content.title = "别忘了取快递"
        content.body = "看看有没有待取的取件码"
        content.sound = .default

        var components = Calendar.current.dateComponents([.hour, .minute], from: date)
        components.second = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: dailyReminderID, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                logger.error("每日提醒注册失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
