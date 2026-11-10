import AppKit

/// The app lives in the menu bar (no Dock icon) until the main window opens.
/// Opening flips it to a regular app so the window can come to the front —
/// `SettingsOpener` does that — and closing the window flips it back here.
@MainActor
enum ActivationPolicy {
    static func mainWindowClosed() {
        NSApp.setActivationPolicy(.accessory)
    }
}
