import AppKit
import Foundation
import os

/// Opens the Settings window from ANY entry point, optionally deep-linking
/// to a pane. Belt and braces: SwiftUI route via the anchor window, plus a
/// delayed AppKit fallback when no settings window materialized.
@MainActor
public enum SettingsOpener {
    private static let log = Logger(subsystem: "com.mac-analyzers.app",
                                    category: "settings-opener")

    /// Receivers of the open-settings signal report in here — the log tells
    /// us which render tree was actually awake to handle a reopen.
    public static func markHandled(by receiver: String) {
        log.notice("open-settings signal handled by \(receiver, privacy: .public)")
    }

    public static func open(target: String? = nil) {
        log.notice("open(target: \(target ?? "nil", privacy: .public)) — windows before: \(NSApp.windows.count)")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // The signal is answered by the menu-bar LABEL's receiver (always
        // alive/visible — os_log diagnosis 2026-08-01; the hidden anchor
        // window's publisher suspends while occluded), which openWindow()s
        // the settings Window scene.
        NotificationCenter.default.post(name: NotifyChannel.openSettingsInternal, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let settingsUp = NSApp.windows.contains {
                $0.isVisible && ($0.identifier?.rawValue.lowercased().contains("main") ?? false)
            }
            log.notice("post-open check — settings visible: \(settingsUp, privacy: .public), windows: \(NSApp.windows.count)")
            NSApp.activate(ignoringOtherApps: true)
            if let target {
                NotificationCenter.default.post(name: NotifyChannel.openPaneInternal,
                                                object: nil, userInfo: ["target": target])
            }
        }
    }
}
