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
        Self.log.notice("applicationShouldHandleReopen fired — hasVisibleWindows: \(flag, privacy: .public)")
        SettingsOpener.open()
        return true
    }


    public func applicationDidFinishLaunching(_ notification: Notification) {
        Self.log.notice("launched — delegate installed")
        NotificationPoster.shared.setup()
        NotifyBridge.start()
        startUpdateWatcher()

        ThermalWatcher.shared.start { title, message in
            NotificationPoster.shared.post(title: title, subtitle: "Thermal",
                                           message: message, sound: nil,
                                           logPath: nil, paneTarget: "monitor")
        }

        startPersistenceWatcher()

        registerLoginItem()

        // `open -a "Mac Analyzers" --args --pane <target>` jumps straight to
        // a settings screen — scripting/testing hook and a power-user door.
        if let flag = CommandLine.arguments.firstIndex(of: "--pane"),
           CommandLine.arguments.indices.contains(flag + 1) {
            let target = CommandLine.arguments[flag + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                SettingsOpener.open(target: target)
            }
        }
    }

    /// `macanalyzers://pane/<target>` — the same jump, but it reaches an app
    /// that is ALREADY running. macOS never re-delivers `--args` to a live
    /// process, so the launch flag above silently did nothing whenever the
    /// app was open, which is nearly always for a menu-bar app.
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "macanalyzers" {
            let target = url.host == "pane"
                ? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : (url.host ?? "")
            guard !target.isEmpty else { continue }
            Self.log.notice("deep link → \(target, privacy: .public)")
            SettingsOpener.open(target: target.replacingOccurrences(of: "/", with: ":"))
        }
    }

    /// Launch + 6-hourly: alert when something NEW installs itself to run at
    /// login/boot. First run seeds the baseline silently.
    private func startPersistenceWatcher() {
        Task { @MainActor in
            while true {
                let additions = await Task.detached(priority: .utility) {
                    PersistenceWatcher.checkForAdditions()
                }.value
                if !additions.isEmpty {
                    let names = additions
                        .map { ($0 as NSString).lastPathComponent }
                        .joined(separator: ", ")
                    NotificationPoster.shared.post(
                        title: additions.count == 1
                            ? "New login/startup item installed"
                            : "\(additions.count) new login/startup items installed",
                        subtitle: "Persistence",
                        message: "\(names). Click to review — nothing was blocked.",
                        sound: nil, logPath: nil, paneTarget: "log:persistence")
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
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
