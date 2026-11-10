import AppKit
import AnalyzersKit
import UserNotifications

/// Handling notification clicks: Open Log, Stop Process, and the body click.
extension NotificationPoster: UNUserNotificationCenterDelegate {

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler done: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let logPath = info["log"] as? String
        let pid = info["pid"] as? Int
        let token = info["token"] as? String ?? ""
        let paneTarget = info["pane"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            let poster = NotificationPoster.shared
            switch action {
            case Self.openLogAction:
                if let logPath { GuardControl.openLog(URL(fileURLWithPath: logPath)) }
            case Self.stopProcessAction:
                if let pid { poster.stopProcess(pid: pid, token: token) }
            default:
                // body click or "Open Mac Analyzers" → the app; a pane
                // target (e.g. update notifications) deep-links to its screen
                if let paneTarget {
                    SettingsOpener.open(target: paneTarget)
                } else {
                    poster.openApp()
                }
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
