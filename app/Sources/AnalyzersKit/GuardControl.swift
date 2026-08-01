import AppKit
import Foundation

/// launchd + convenience actions the UI triggers. All user-domain
/// (gui/<uid>) — exactly what a logged-in user's own process may manage.
@MainActor
public enum GuardControl {

    public static let guardLabel = "com.mac-analyzers.memory-guard"
    public static let memoryCleanLabel = "com.mac-analyzers.memory-autoclean.daily"
    public static let storageCleanLabel = "com.mac-analyzers.storage-autoclean.daily"
    public static let storageDeepLabel = "com.mac-analyzers.storage-autoclean.deep"

    /// Restart the guard agent so freshly-saved tunables take effect
    /// (the guard reads its env once at startup).
    public static func restartGuard() {
        launchctl(["kickstart", "-k", "gui/\(getuid())/\(guardLabel)"])
    }

    /// Kick an on-demand run of a scheduled job.
    public static func runNow(_ label: String) {
        launchctl(["kickstart", "gui/\(getuid())/\(label)"])
    }

    /// USER-initiated stop — a different contract from the guard's automatic
    /// kills (which stay dev-tooling-only): the user may stop anything, same
    /// as Activity Monitor. GUI apps get a graceful terminate (⌘Q semantics,
    /// save dialogs still appear); everything else gets SIGTERM.
    public static func stopProcess(_ proc: LiveProcess) {
        if !proc.isDev,
           let app = NSRunningApplication(processIdentifier: pid_t(proc.pid)) {
            app.terminate()
            return
        }
        kill(pid_t(proc.pid), SIGTERM)
    }

    /// Relaunch just this app — the light alternative to a Mac restart: the
    /// detached child survives our exit and opens a fresh instance.
    public static func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.7; /usr/bin/open -g \"\(bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// Run the repo's upgrade.command in Terminal — visible progress: pull,
    /// rebuild, refresh agents, relaunch. Settings are never touched.
    public static func runUpgrade() {
        NSWorkspace.shared.open(AnalyzersPaths.suiteRoot.appending(path: "upgrade.command"))
    }

    /// Deep-link to this app's pane in System Settings → Notifications.
    public static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func openLog(_ url: URL) {
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: textEdit,
                                configuration: NSWorkspace.OpenConfiguration()) { _, err in
            if err != nil { NSWorkspace.shared.open(url) }
        }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
