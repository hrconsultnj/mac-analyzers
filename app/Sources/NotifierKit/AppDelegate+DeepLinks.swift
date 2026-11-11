import AppKit
import AnalyzersKit
import os

/// Deep links: macanalyzers://pane/<target> reaching an already-running app.
extension AppDelegate {

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
}
