import Foundation

/// Name of the distributed notification the CLI shim posts and the app observes.
public enum NotifyChannel {
    /// Posted by this app and by the notify CLI.
    public static let name = "com.sparehold.notify"
    /// Still observed so a Sparehold notifier, and ProKit, reach this app.
    public static let legacyName = "com.mac-analyzers.notify"
    public static let appBundleID = AppIdentity.bundleID
    public static let legacyAppBundleID = AppIdentity.legacyBundleID
    /// In-process signal: "open the app's window" (Dock click, notification
    /// default action); userInfo["target"] optionally names where the link
    /// lands. Posted by AppKit code, observed by the menu-bar label and the
    /// SwiftUI anchor window, which hold the openWindow environment action.
    public static let openSettingsInternal = Notification.Name("com.sparehold.open-settings")
    public static let legacyOpenSettings = Notification.Name("com.mac-analyzers.open-settings")
    /// In-process signal: "navigate the main window to this target" — userInfo["target"]
    /// carries a deep-link target string ("activity", "guard", "log:<kind>", "monitor").
    public static let openPaneInternal = Notification.Name("com.sparehold.open-pane")
    public static let legacyOpenPane = Notification.Name("com.mac-analyzers.open-pane")
    /// In-process signal: "show or hide the main window's sidebar" — what the View menu item and the toolbar button do.
    /// The snapshot tool sends it to check the window keeps its size.
    public static let toggleSidebarInternal = Notification.Name("com.sparehold.toggle-sidebar")
    public static let legacyToggleSidebar = Notification.Name("com.mac-analyzers.toggle-sidebar")
}
