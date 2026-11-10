import SwiftUI
import AnalyzersKit
import UIComponents

/// Run the audit and apply fences as jobs, and load the latest audit.
extension SpotlightAuditView {

    // MARK: - actions

    /// `--dry-run`: status + verdict + exposure, nothing touched.
    func runAudit() {
        job = jobs.enqueue(JobRequest(kind: .spotlight, intent: .preview), trigger: .user)
    }

    /// The audit this screen's fences would be applied from: finished well, in
    /// the store. The kernel builds an apply only from such a preview, so the
    /// button waits for one.
    var reviewedAudit: Job? {
        guard let preview = jobs.latest(.spotlight, intents: [.preview]),
              case .succeeded = preview.state else { return nil }
        return preview
    }

    /// `--apply`: fences every unfenced dev directory under the configured
    /// roots. Gated by the confirmation dialog — this is the one action
    /// here that isn't instantly, individually reversible the way a single
    /// row's Fence/Unfence is (it acts on everything at once). Built from the
    /// audit the user just saw, never on its own.
    func applyFences() {
        guard let preview = reviewedAudit else { return }
        job = jobs.apply(from: preview, approved: .everything)
    }

    var runPhase: RunPhase {
        guard let job else { return .idle }
        switch job.state {
        case .queued:
            return .running("Waiting for the running job to finish…")
        case .running:
            return .running(job.intent == .apply ? "Fencing unfenced dev directories…"
                                                 : "Running audit — nothing is being changed…")
        case .succeeded:
            return .done(job.intent == .apply ? "Fences applied." : "Audit complete.")
        case .failed(let failure):
            return .failed(failure.message)
        case .cancelled(let partial):
            return partial ? .failed("Stopped. Fences already placed stay — each one can be removed with Unfence.")
                           : .idle
        }
    }

    func adoptCurrentJob() {
        job = jobs.latest(.spotlight, intents: [.preview, .apply])
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
