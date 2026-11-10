import Foundation

/// Name of the distributed notification the CLI shim posts and the app observes.
public enum NotifyChannel {
    public static let name = "com.mac-analyzers.notify"
    public static let appBundleID = "com.mac-analyzers.app"
    /// In-process signal: "open the Settings window" (Dock click, notification
    /// default action). Posted by AppKit code, observed by the SwiftUI anchor
    /// window, which holds the openSettings environment action.
    public static let openSettingsInternal = Notification.Name("com.mac-analyzers.open-settings")
    /// In-process signal: "navigate Settings to this pane" — userInfo["target"]
    /// carries a route string ("activity", "logs", "log:<kind>", "monitor").
    public static let openPaneInternal = Notification.Name("com.mac-analyzers.open-pane")
}
