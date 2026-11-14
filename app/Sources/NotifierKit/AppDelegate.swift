import AppKit
import AnalyzersKit
import os

/// Minimal AppKit bridge for the SwiftUI lifecycle: wires the notification
/// poster + the distributed-notification listener at launch, and registers
/// the app as a Login Item so the menu bar survives reboots.
///
/// This file is the lifecycle only (reopen, launch). One job per file next to it:
///   AppDelegate+DeepLinks.swift  macanalyzers:// links into a running app
///   AppDelegate+Watchers.swift   new login items, new releases
///   AppDelegate+LoginItem.swift  registering the app as a login item
///   AppDelegate+FirstRun.swift   opening Setup on a new or broken Mac
///   AppDelegate+Quit.swift       asking before a quit that would orphan a running job
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    static let log = Logger(subsystem: "com.mac-analyzers.app",
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
        startRulesWatcher()

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
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.openSetupIfUnconfigured()
            }
        }
    }
}
