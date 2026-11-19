import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func prepare() {
        // Delegate is configured in init. Authorization is requested lazily
        // before the first successful-send notification.
    }

    func notifySuccess(recipient: String, detail: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "一键邮 · 发送成功"
            content.body = "已发送到 \(recipient)\n\(detail)"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "oneclickmail.sent.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
