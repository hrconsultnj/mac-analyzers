import Foundation

/// Name of the distributed notification the CLI shim posts and the app observes.
public enum NotifyChannel {
    public static let name = "com.mac-analyzers.notify"
    public static let appBundleID = "com.mac-analyzers.app"
    /// In-process signal: "open the app's window" (Dock click, notification
    /// default action); userInfo["target"] optionally names where the link
    /// lands. Posted by AppKit code, observed by the menu-bar label and the
    /// SwiftUI anchor window, which hold the openWindow environment action.
    public static let openSettingsInternal = Notification.Name("com.mac-analyzers.open-settings")
    /// In-process signal: "navigate the main window to this target" — userInfo["target"]
    /// carries a deep-link target string ("activity", "guard", "log:<kind>", "monitor").
    public static let openPaneInternal = Notification.Name("com.mac-analyzers.open-pane")
}
