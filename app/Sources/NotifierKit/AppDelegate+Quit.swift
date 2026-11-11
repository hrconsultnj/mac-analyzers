import AppKit
import AnalyzersKit

/// Quitting while a job runs. The menu-bar app has no ordinary window-close
/// quit: the footer's Quit, ⌘Q and the Dock all end in `NSApp.terminate`, so the
/// one place to ask is the delegate's `applicationShouldTerminate`.
///
/// A job's process tree outlives the app (it is launched, not owned), so a
/// silent quit would leave it running with nothing to stop it and no record of
/// who started it. Instead the person chooses:
///  - Stop and Quit: stop the tree, wait (bounded) for the index line, quit;
///  - Quit and Let It Finish: write the index line now, quit, the job goes on;
///  - Cancel: stay.
///
/// A quit macOS starts (logout, restart, shutdown) never shows the dialog:
/// nobody is there to answer, and a held-up restart is worse than a stopped
/// job. For those the jobs are stopped, with a short bound, and the app replies.
@MainActor
public enum QuitGuard {
    /// The app's one job store, handed over by the app once it exists.
    public static weak var jobs: JobStore?
}

extension AppDelegate {

    /// Termination is now certain. A Restart asked for earlier starts its
    /// relauncher here — not before the person has answered the dialog.
    public func applicationWillTerminate(_ notification: Notification) {
        GuardControl.startRelauncherIfRequested()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let jobs = QuitGuard.jobs, jobs.hasWork else { return .terminateNow }

        if Self.quitIsFromTheSystem {
            Task { @MainActor in
                await jobs.stopEverything(timeout: .seconds(3))
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        let running = jobs.running
        let waiting = jobs.queued.count
        alert.messageText = running != nil
            ? "A cleanup or check is still running."
            : "\(waiting) job\(waiting == 1 ? " is" : "s are") waiting to run."
        var detail = running != nil
            ? "Quitting does not stop it by itself: it keeps running in the background until it finishes. You can stop it now, or let it finish."
            : "They will not start once Mac Analyzers has quit."
        if running != nil, waiting > 0 {
            detail += " The \(waiting) waiting job\(waiting == 1 ? "" : "s") will not start."
        }
        alert.informativeText = detail
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Quit and Let It Finish")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                await jobs.stopEverything()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            Task { @MainActor in
                await jobs.recordRunningForQuit()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        default:
            GuardControl.relaunchAfterQuit = false   // a Restart that was cancelled must not relaunch a later quit
            return .terminateCancel
        }
    }

    /// The quit Apple event carries a reason (`keyAEQuitReason`, 'why?') when
    /// macOS is logging out, restarting, shutting down or quitting everything.
    /// A quit the person asked for (⌘Q, the menu, the Dock) has none.
    ///
    /// The SDK header (AERegistry.h) documents the reason as a PARAMETER of the
    /// quit event and lists `kAEQuitAll`, `kAEShutDown`, `kAERestart` and
    /// `kAEReallyLogOut`; code in the wild reads it as an ATTRIBUTE. The two
    /// are separate stores — a value set as one is invisible to the other — so
    /// both are read. A real logout cannot be exercised without a person, and
    /// missing it would hold up an unattended restart behind a dialog.
    private static var quitIsFromTheSystem: Bool {
        func code(_ text: String) -> OSType { text.utf8.reduce(0) { ($0 << 8) | OSType($1) } }
        let reasons: Set<OSType> = [
            code("quia"), code("shut"), code("rest"), code("rlgo"),   // the documented reasons
            code("logo"), code("rrst"), code("rsdn"),                 // loginwindow's own events, seen in practice
        ]
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        let why = AEKeyword(code("why?"))
        guard let reason = (event.attributeDescriptor(forKeyword: why)
                            ?? event.paramDescriptor(forKeyword: why))?.enumCodeValue else { return false }
        return reasons.contains(reason)
    }
}
