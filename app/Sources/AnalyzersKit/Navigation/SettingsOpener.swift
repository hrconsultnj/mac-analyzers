import AppKit
import Foundation
import os

/// Opens the app's window from ANY entry point, optionally deep-linking to a
/// screen. The target travels with the open signal so the receiver can decide
/// which window it belongs in before opening one; the same target is posted
/// again once the window is up, for the screen to navigate.
@MainActor
public enum SettingsOpener {
    private static let log = Logger(subsystem: AppIdentity.bundleID,
                                    category: "settings-opener")

    /// Receivers of the open-window signal report in here — the log tells
    /// us which render tree was actually awake to handle a reopen.
    public static func markHandled(by receiver: String) {
        log.notice("open-window signal handled by \(receiver, privacy: .public)")
    }

    /// The screen the last open asked for, until a window has gone to it. A window that comes up after the
    /// signal below was posted (a cold start that takes longer than the short wait) takes it when it appears,
    /// so a link from a notification never lands on the restored screen instead of its target.
    private static var pendingTarget: String?

    /// The target still waiting for a window, taken once: whoever takes it navigates, nobody else does.
    public static func takePendingTarget() -> String? {
        defer { pendingTarget = nil }
        return pendingTarget
    }

    public static func open(target: String? = nil) {
        pendingTarget = target
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
            // a window that is already listening goes now; one that is not yet up takes it when it appears
            if let target = takePendingTarget() {
                NotificationCenter.default.post(name: NotifyChannel.openPaneInternal,
                                                object: nil, userInfo: ["target": target])
            }
        }
    }
}
