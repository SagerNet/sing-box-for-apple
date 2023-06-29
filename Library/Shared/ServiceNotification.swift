import Foundation
import UserNotifications

public enum ServiceNotification {
    private static let delegate = Delegate()

    public static func register() {
        UNUserNotificationCenter.current().delegate = delegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) {
            _, _ in
        }
    }

    private static var listener: ((UNNotificationContent) -> Void)?

    public static func setServiceNotificationListener(listener: @escaping (UNNotificationContent) -> Void) {
        ServiceNotification.listener = listener
    }

    public static func removeServiceNotificationListener() {
        ServiceNotification.listener = nil
    }

    public static func postServiceNotification(content: UNNotificationContent) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "service-notification", content: content, trigger: nil))
    }

    public static func postServiceNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        postServiceNotification(content: content)
    }

    private class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            NSLog("userNotificationCenter")
            if let listener = ServiceNotification.listener {
                listener(notification.request.content)
                return []
            } else {
                return [.alert]
            }
        }
    }
}
