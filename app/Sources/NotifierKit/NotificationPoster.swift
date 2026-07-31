import AppKit
import AnalyzersKit
import UserNotifications

/// Posts suite notifications and handles their clicks. Because the menu-bar
/// app is persistent, the delegate is always alive — clicks are handled by a
/// live delegate, never the cold-relaunch path the standalone notifier needed.
@MainActor
public final class NotificationPoster: NSObject {

    public static let shared = NotificationPoster()

    private let center = UNUserNotificationCenter.current()
    private static let categoryID = "MAC_ANALYZERS_EVENT"
    private static let openLogAction = "OPEN_LOG"

    /// Call once at app launch: delegate, categories, authorization.
    public func setup() {
        center.delegate = self
        let openLog = UNNotificationAction(identifier: Self.openLogAction,
                                           title: "Open Log", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.categoryID,
                                              actions: [openLog],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Maintenance action: re-ask macOS for notification permission when it's
    /// still undetermined; otherwise report the current state and open the
    /// System Settings pane so the user can flip it themselves (apps cannot
    /// reset their own grant — that lever is deliberately the user's).
    public func reRequestPermission(completion: @escaping @MainActor (String) -> Void) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .notDetermined:
                    self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        Task { @MainActor in
                            completion(granted ? "Permission granted." : "Permission declined — enable it in System Settings.")
                        }
                    }
                case .denied:
                    completion("Currently denied — opening System Settings so you can re-enable it.")
                    GuardControl.openNotificationSettings()
                default:
                    completion("Already allowed — opening System Settings for style/preview options.")
                    GuardControl.openNotificationSettings()
                }
            }
        }
    }

    public func post(title: String, message: String, sound: String?, logPath: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = title
        if let sound, !sound.isEmpty {
            content.sound = sound.lowercased() == "default"
                ? .default
                : UNNotificationSound(named: UNNotificationSoundName(sound + ".aiff"))
        }
        if let logPath { content.userInfo = ["log": logPath] }
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        center.add(request)
    }
}

extension NotificationPoster: UNUserNotificationCenterDelegate {

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler done: @escaping () -> Void
    ) {
        let logPath = response.notification.request.content.userInfo["log"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            if let logPath,
               action == Self.openLogAction || action == UNNotificationDefaultActionIdentifier {
                GuardControl.openLog(URL(fileURLWithPath: logPath))
            }
        }
        done()
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        done([.banner, .sound])
    }
}
