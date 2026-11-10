import SwiftUI
import AnalyzersKit
import UIComponents

/// Run the audit, apply fences, and load the latest audit.
extension SpotlightAuditView {

    // MARK: - actions

    /// `--dry-run`: status + verdict + exposure, nothing touched.
    func runAudit() async {
        runPhase = .running("Running audit — nothing is being changed…")
        let result = await ActionRunner.run(script: AnalyzersPaths.spotlightAuditScript, args: ["--dry-run"])
        guard result.exitCode == 0 else {
            runPhase = .failed(ExitExplanation.explain(exitCode: result.exitCode, verb: "run the audit"))
            return
        }
        runPhase = .done("Audit complete.")
        await load(force: true)
    }

    /// `--apply`: fences every unfenced dev directory under the configured
    /// roots. Gated by the confirmation dialog — this is the one action
    /// here that isn't instantly, individually reversible the way a single
    /// row's Fence/Unfence is (it acts on everything at once).
    func applyFences() async {
        runPhase = .running("Fencing unfenced dev directories…")
        let result = await ActionRunner.run(script: AnalyzersPaths.spotlightAuditScript, args: ["--apply"])
        guard result.exitCode == 0 else {
            runPhase = .failed(ExitExplanation.explain(exitCode: result.exitCode, verb: "apply fences"))
            return
        }
        runPhase = .done("Fences applied.")
        await load(force: true)
    }

    // MARK: - load

    /// `force` bypasses the LoadCoordinator's 3s TTL for this call only —
    /// needed right after a script run, where the log just changed and the
    /// cached parse (same call-site key as the normal `.task`/Refresh load)
    /// would otherwise still be "fresh enough" to serve stale.
    func load(force: Bool = false) async {
        await awaitLoad({
            LogParser.runs(for: .spotlightAudit).first.map {
                SpotlightAuditParser.parse(runHeader: $0.header, lines: $0.lines)
            }
        }, ttl: force ? 0 : 3) { run = $0 }
    }
}
