import AppKit
import AnalyzersKit
import os
import ServiceManagement
import UserNotifications

/// Minimal AppKit bridge for the SwiftUI lifecycle: wires the notification
/// poster + the distributed-notification listener at launch, and registers
/// the app as a Login Item so the menu bar survives reboots.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let log = Logger(subsystem: "com.mac-analyzers.app",
                                    category: "app-delegate")

    /// Dock-tile click while running (LSUIElement apps still get reopen
    /// events from a kept Dock icon) → open Settings. A click when the app
    /// is NOT running simply launches it — macOS handles that part.
    /// Instrumented: `log show --predicate 'subsystem == "com.mac-analyzers.app"'
    /// --last 5m` shows whether the event is even delivered on a Dock click.
    public func applicationShouldHandleReopen(_ sender: NSApplication,
                                              hasVisibleWindows flag: Bool) -> Bool {
        Self.log.info("applicationShouldHandleReopen fired — hasVisibleWindows: \(flag, privacy: .public)")
        SettingsOpener.open()
        return true
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationPoster.shared.setup()
        NotifyBridge.start()
        startUpdateWatcher()

        registerLoginItem()
    }

    /// Checks for a newer release at launch and every 6 hours; notifies ONCE
    /// per version — clicking the notification opens the Update pane.
    private func startUpdateWatcher() {
        Task { @MainActor in
            while true {
                if let latest = await UpdateChecker.latestVersion(),
                   UpdateChecker.isNewer(latest, than: UpdateChecker.installedVersion),
                   UserDefaults.standard.string(forKey: "updateNotifiedFor") != latest {
                    NotificationPoster.shared.post(
                        title: "Mac Analyzers update available",
                        subtitle: "v\(latest)",
                        message: "You're on v\(UpdateChecker.installedVersion). Click to open the Update screen and install with one click.",
                        sound: nil, logPath: nil, paneTarget: "update")
                    UserDefaults.standard.set(latest, forKey: "updateNotifiedFor")
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    private func registerLoginItem() {
        // Self-register as a Login Item (macOS notifies the user it was
        // added, with a link to System Settings — the transparent, Apple-
        // sanctioned path). Idempotent: skip when already enabled; if the
        // user removes it in System Settings, macOS remembers the opt-out.
        //
        // One-time migration: when first launched from /Applications (the
        // canonical install), re-register so the login item points here and
        // not at the repo build-artifact copy.
        let inApplications = Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        let migratedKey = "loginItemMovedToApplications"
        if inApplications, !UserDefaults.standard.bool(forKey: migratedKey) {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: migratedKey)
        } else if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }
}
