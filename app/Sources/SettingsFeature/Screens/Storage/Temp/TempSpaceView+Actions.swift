import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Run audit and eject as jobs, open Actions, and loading the latest audit.
extension TempSpaceView {

    // MARK: - actions

    /// The audit is a preview job of the temp cleaner — the same job the
    /// Actions screen adopts, so a review can follow it directly.
    func runAudit() {
        job = jobs.enqueue(JobRequest(kind: .tempClean, intent: .preview), trigger: .user)
    }

    /// `--eject <mountpoint>`: the engine ejects dependents first (an image
    /// opened from inside this one), never forced, then re-audits — so the
    /// pane reloads into a run that already reflects the eject.
    func eject(_ mount: TempMount) {
        ejecting = nil
        ejectProblem = nil
        job = jobs.enqueue(JobRequest(kind: .eject, intent: .run,
                                      options: JobOptions(mountPoint: mount.mountPoint)),
                           trigger: .user)
    }

    /// The line under the action row, read off the job.
    var runPhase: RunPhase {
        guard let job else { return .idle }
        let image = job.request.options.mountPoint.map { ($0 as NSString).lastPathComponent } ?? "disk image"
        switch job.state {
        case .queued:
            return .running("Waiting for the running job to finish…")
        case .running:
            return .running(job.kind == .eject
                            ? "Ejecting \(image)…"
                            : "Auditing /tmp, /var and agent folders — nothing is being changed…")
        case .succeeded:
            if job.kind == .eject { return ejectProblem.map { .failed($0) } ?? .done("Ejected \(image).") }
            return .done("Audit complete.")
        case .failed(let failure):
            return .failed(failure.message)
        case .cancelled:
            return .idle
        }
    }

    func adoptCurrentJob() {
        job = jobs.latest { ($0.kind == .tempClean && $0.intent == .preview) || $0.kind == .eject }
    }

    /// The job ended well: read what it wrote. After an eject, check that the
    /// image really went — the script can succeed while something still reads it.
    func jobSucceeded() async {
        await load(force: true)
        guard let job, job.kind == .eject, let mountPoint = job.request.options.mountPoint else { return }
        let after = run?.mounts.first { $0.mountPoint == mountPoint }
        if after?.status == .ejectFailed {
            let name = (mountPoint as NSString).lastPathComponent
            ejectProblem = "Couldn't eject \(name) — something is still reading from it. Close it there, then try again."
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
