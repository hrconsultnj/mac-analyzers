import AppKit
import ServiceManagement
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

    /// USER-initiated quit of a whole GROUP — "close Opera", not "end one of
    /// its 30 processes". An app's main process gets the ⌘Q request and its
    /// helpers leave with it (save prompts still appear); a tool's top-level
    /// processes get the polite stop and take what they started with them.
    /// Same contract as `stopProcess`: the user may stop their own things;
    /// macOS's are never in scope (`QuitScope.unavailable`).
    public static func quit(_ scope: CensusGroup.QuitScope) {
        switch scope {
        case .app(let mainPIDs):
            for pid in mainPIDs {
                if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                    app.terminate()
                } else {
                    kill(pid_t(pid), SIGTERM)
                }
            }
        case .tools(let rootPIDs):
            for pid in rootPIDs { kill(pid_t(pid), SIGTERM) }
        case .unavailable:
            break
        }
    }

    /// Relaunch just this app — the light alternative to a Mac restart: the
    /// detached child survives our exit and opens a fresh instance.
    /// Set by `restartApp`, cleared when the quit is cancelled, acted on when
    /// the app is really terminating (`startRelauncherIfRequested`).
    public static var relaunchAfterQuit = false

    public static func restartApp() {
        // With a job running, quitting asks first. So Restart only RECORDS that a
        // relaunch is wanted; the relauncher starts once termination is certain
        // (the app delegate's applicationWillTerminate). Started here, it would
        // outlive a cancelled quit and relaunch the app on some later, unrelated quit.
        relaunchAfterQuit = true
        NSApp.terminate(nil)
    }

    /// Start a small shell that waits for THIS process to be gone, then opens
    /// the app again. Waiting on the pid — not a fixed pause — because stopping
    /// a running job can take a few seconds. Bounded to one minute.
    public static func startRelauncherIfRequested() {
        guard relaunchAfterQuit else { return }
        relaunchAfterQuit = false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c",
                       "n=0; while kill -0 \"$1\" 2>/dev/null && [ $n -lt 300 ]; do sleep 0.2; n=$((n+1)); done; /usr/bin/open -g \"$2\"",
                       "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        try? p.run()
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

    /// Stop opening at login — part of turning the product off cleanly.
    public static func disableLoginItem() {
        try? SMAppService.mainApp.unregister()
    }

    /// Honours the same ANALYZERS_LOG_VIEWER preference the notification
    /// path uses — the in-app buttons used to ignore it and always open
    /// TextEdit, which made the Settings picker look broken.
    public static func openLog(_ url: URL) {
        let preferred = ConfigStore.currentLogViewer()
        let candidates = [
            "/System/Applications/\(preferred).app",
            "/Applications/\(preferred).app",
            "/System/Applications/Utilities/\(preferred).app",
            "/System/Applications/TextEdit.app",
        ].map { URL(fileURLWithPath: $0) }
        guard let app = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app,
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
