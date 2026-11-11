import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications
import AnalyzersKit
import NotifierKit
import UIComponents

/// Detecting each check: loading the report, notifications and the login item.
extension SetupSettingsView {

    // MARK: - probing

    func load() async {
        // the two system permissions answer asynchronously; everything else
        // is a file/launchctl read that belongs off the main actor
        let notifications = await notificationCheck()
        let login = loginItemCheck()
        await awaitLoad({ SetupAudit.probe(notifications: notifications, loginItem: login) },
                        ttl: 1) { report = $0 }
    }

    private func notificationCheck() async -> SetupCheck {
        // A bare executable has no app bundle, and the notification center throws without
        // one (a tool quirk: the installed app always has a bundle). Say so instead.
        guard Bundle.main.bundleIdentifier != nil else {
            return SetupCheck(
                id: "notifications", title: "Alerts when something happens",
                why: "Tells you when an app was stopped or space was reclaimed, so nothing happens behind your back.",
                verdict: .unset,
                detail: "Can't be checked here: this is running without an app bundle.",
                repair: .none, repairTitle: nil)
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            let alerts = settings.alertSetting == .enabled
            return SetupCheck(
                id: "notifications", title: "Alerts when something happens",
                why: "Tells you when an app was stopped or space was reclaimed, so nothing happens behind your back.",
                verdict: alerts ? .ready : .degraded,
                detail: alerts
                    ? "Allowed, and alerts are visible."
                    : "Allowed, but alerts are switched off in System Settings, so you will only see them in Notification Centre.",
                repair: alerts ? .sendTestNotification : .openNotificationSettings,
                repairTitle: alerts ? "Send a test" : "Open the setting")
        case .denied:
            return SetupCheck(
                id: "notifications", title: "Alerts when something happens",
                why: "Tells you when an app was stopped or space was reclaimed, so nothing happens behind your back.",
                verdict: .degraded,
                detail: "Turned off. Mac Analyzers still works, but it will act silently.",
                repair: .openNotificationSettings, repairTitle: "Open the setting")
        default:
            return SetupCheck(
                id: "notifications", title: "Alerts when something happens",
                why: "Tells you when an app was stopped or space was reclaimed, so nothing happens behind your back.",
                verdict: .unset,
                detail: "Not asked yet.",
                repair: .requestNotifications, repairTitle: "Allow alerts")
        }
    }

    /// Read live every time. A cached login-item status is how an app ends up
    /// claiming it starts at login when the user removed it last week.
    private func loginItemCheck() -> SetupCheck {
        let why = "Puts the menu-bar icon back after a restart. The background protection runs either way."
        switch SMAppService.mainApp.status {
        case .enabled:
            return SetupCheck(id: "login", title: "Opens when you log in", why: why,
                              verdict: .ready, detail: "Enabled.")
        case .requiresApproval:
            return SetupCheck(id: "login", title: "Opens when you log in", why: why,
                              verdict: .degraded,
                              detail: "Waiting for your approval in System Settings › General › Login Items.",
                              repair: .openLoginItemSettings, repairTitle: "Open the setting")
        case .notFound:
            return SetupCheck(id: "login", title: "Opens when you log in", why: why,
                              verdict: .degraded,
                              detail: "macOS does not recognise this copy of the app. Move it to your Applications folder and try again.",
                              repair: .enableLoginItem, repairTitle: "Try Again")
        default:
            return SetupCheck(id: "login", title: "Opens when you log in", why: why,
                              verdict: .unset, detail: "Not enabled.",
                              repair: .enableLoginItem, repairTitle: "Turn it on")
        }
    }
}
