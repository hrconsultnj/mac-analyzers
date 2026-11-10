import AppKit
import Foundation
import os

/// Opens the app's window from ANY entry point, optionally deep-linking to a
/// screen. The target travels with the open signal so the receiver can decide
/// which window it belongs in before opening one; the same target is posted
/// again once the window is up, for the screen to navigate.
@MainActor
public enum SettingsOpener {
    private static let log = Logger(subsystem: "com.mac-analyzers.app",
                                    category: "settings-opener")

    /// Receivers of the open-window signal report in here — the log tells
    /// us which render tree was actually awake to handle a reopen.
    public static func markHandled(by receiver: String) {
        log.notice("open-window signal handled by \(receiver, privacy: .public)")
    }

    public static func open(target: String? = nil) {
        log.notice("open(target: \(target ?? "nil", privacy: .public)) — windows before: \(NSApp.windows.count)")
        ActivationPolicy.windowOpening()
        // The signal is answered by the menu-bar LABEL's receiver (always
        // alive/visible — os_log diagnosis 2026-08-01; the hidden anchor
        // window's publisher suspends while occluded), which openWindow()s
        // the main Window scene.
        NotificationCenter.default.post(name: NotifyChannel.openSettingsInternal, object: nil,
                                        userInfo: target.map { ["target": $0] })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let windowUp = NSApp.windows.contains {
                $0.isVisible && ($0.identifier?.rawValue.lowercased().contains("main") ?? false)
            }
            log.notice("post-open check — main window visible: \(windowUp, privacy: .public), windows: \(NSApp.windows.count)")
            NSApp.activate(ignoringOtherApps: true)
            if let target {
                NotificationCenter.default.post(name: NotifyChannel.openPaneInternal,
                                                object: nil, userInfo: ["target": target])
            }
        }
    }
}
