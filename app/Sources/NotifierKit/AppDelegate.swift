import AppKit
import AnalyzersKit
import ServiceManagement
import UserNotifications

/// Minimal AppKit bridge for the SwiftUI lifecycle: wires the notification
/// poster + the distributed-notification listener at launch, and registers
/// the app as a Login Item so the menu bar survives reboots.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Dock-tile click while running (LSUIElement apps still get reopen
    /// events from a kept Dock icon) → open Settings. A click when the app
    /// is NOT running simply launches it — macOS handles that part.
    public func applicationShouldHandleReopen(_ sender: NSApplication,
                                              hasVisibleWindows flag: Bool) -> Bool {
        SettingsOpener.open()
        return true
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationPoster.shared.setup()
        NotifyBridge.start()

        // Self-register as a Login Item (macOS notifies the user it was
        // added, with a link to System Settings — the transparent, Apple-
        // sanctioned path). Idempotent: skip when already enabled; if the
        // user removes it in System Settings, macOS remembers the opt-out.
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }
}
