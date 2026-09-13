import BatteryAlerts
import Foundation
import UserNotifications

final class NotificationController: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private enum Action {
        static let snooze = "SNOOZE_30_MINUTES"
        static let lowCategory = "LOW_BATTERY"
    }

    var onSnooze: (@Sendable (UUID) -> Void)?

    func configure() {
        let snooze = UNNotificationAction(identifier: Action.snooze, title: "Snooze for 30 Minutes")
        let category = UNNotificationCategory(
            identifier: Action.lowCategory,
            actions: [snooze],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([category])
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ alert: BatteryAlert, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = alert.kind == .low ? "Low Battery" : "Charging Complete"
        content.body = "\(alert.deviceName) is at \(alert.level)%."
        content.userInfo = ["deviceID": alert.deviceID.uuidString]
        content.categoryIdentifier = alert.kind == .low ? Action.lowCategory : ""
        if sound { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard response.actionIdentifier == Action.snooze,
              let value = response.notification.request.content.userInfo["deviceID"] as? String,
              let id = UUID(uuidString: value)
        else { return }
        onSnooze?(id)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
