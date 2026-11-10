import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Run audit, eject, open Actions, and loading the latest audit.
extension TempSpaceView {

    // MARK: - actions

    func runAudit() async {
        runPhase = .running("Auditing /tmp, /var and agent folders — nothing is being changed…")
        let result = await ActionRunner.run(script: AnalyzersPaths.tempCleanScript, args: ["--dry-run"])
        guard result.exitCode == 0 else {
            runPhase = .failed(ExitExplanation.explain(exitCode: result.exitCode, verb: "run the audit"))
            return
        }
        runPhase = .done("Audit complete.")
        await load(force: true)
    }

    /// `--eject <mountpoint>`: the engine ejects dependents first (an image
    /// opened from inside this one), never forced, then re-audits — so the
    /// pane reloads into a run that already reflects the eject.
    func eject(_ mount: TempMount) async {
        ejecting = nil
        let name = (mount.mountPoint as NSString).lastPathComponent
        runPhase = .running("Ejecting \(name)…")
        let result = await ActionRunner.run(script: AnalyzersPaths.tempCleanScript,
                                            args: ["--eject", mount.mountPoint])
        guard result.exitCode == 0 else {
            runPhase = .failed(ExitExplanation.explain(exitCode: result.exitCode, verb: "eject \(name)"))
            return
        }
        await load(force: true)
        let after = run?.mounts.first { $0.mountPoint == mount.mountPoint }
        if after?.status == .ejectFailed {
            runPhase = .failed("Couldn't eject \(name) — something is still reading from it. Close it there, then try again.")
        } else {
            runPhase = .done("Ejected \(name).")
        }
    }

    func openActions() {
        navigator.push(.storage(.review(ActionsSettingsView.Cleaner.tempClean.rawValue)))
    }

    // MARK: - load

    /// `force` bypasses the LoadCoordinator TTL right after a script run —
    /// the log just changed and the cached parse would otherwise be served.
    func load(force: Bool = false) async {
        await awaitLoad({
            LogParser.runs(for: .tempSpace).first.map {
                TempCleanParser.parse(runHeader: $0.header, lines: $0.lines)
            }
        }, ttl: force ? 0 : 3) { run = $0 }
    }
}
