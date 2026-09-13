import AppKit
import CoreBluetooth
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class PermissionController: ObservableObject {
    @Published private(set) var bluetooth = "Not Determined"
    @Published private(set) var notifications = "Not Determined"

    func refresh() {
        switch CBManager.authorization {
        case .notDetermined: bluetooth = "Not Determined"
        case .restricted: bluetooth = "Restricted"
        case .denied: bluetooth = "Denied"
        case .allowedAlways: bluetooth = "Allowed"
        @unknown default: bluetooth = "Unavailable"
        }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let value: String
            switch settings.authorizationStatus {
            case .notDetermined: value = "Not Determined"
            case .denied: value = "Denied"
            case .authorized: value = "Allowed"
            case .provisional: value = "Provisional"
            case .ephemeral: value = "Temporary"
            @unknown default: value = "Unavailable"
            }
            notifications = value
        }
    }

    func openBluetoothSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
    }

    func openNotificationSettings() {
        if #available(macOS 13.0, *) {
            openSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        } else {
            openSettings("x-apple.systempreferences:com.apple.preference.notifications")
        }
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
