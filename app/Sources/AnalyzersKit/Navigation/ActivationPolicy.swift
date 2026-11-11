import AppKit

/// The app lives in the menu bar (no Dock icon) until its main window opens.
/// Opening flips it to a regular app and activates it, so the window can come
/// to the front; closing the window flips it back. Every entry point that
/// opens the window and the window's own close go through here.
@MainActor
public enum ActivationPolicy {
    public static func windowOpening() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func windowClosed() {
        NSApp.setActivationPolicy(.accessory)
    }
}
