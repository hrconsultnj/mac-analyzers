import SwiftUI
import AnalyzersKit
import UIComponents

/// Talking to the engine through the job store: preview, apply, finding this
/// cleaner's jobs again, reading the run back from the job, and resetting the
/// screen. Nothing here runs a script itself.
extension ActionsSettingsView {

    var jobOptions: JobOptions {
        JobOptions(deep: cleaner == .storageClean && storageDeep,
                   permanent: cleaner == .tempClean && tempPermanent)
    }

    /// Both jobs' stages, for `onChange`.
    var jobStamps: [JobStamp] { [JobStamp(previewJob), JobStamp(applyJob)] }

    // MARK: - starting jobs

    func preview() {
        resetRuns()
        lastOutput = ""
        applyJob = nil
        previewJob = jobs.enqueue(JobRequest(kind: cleaner.jobKind, intent: .preview, options: jobOptions),
                                  trigger: .user)
        syncFromJobs()
    }

    /// Built from the finished preview with exactly what is ticked. The store
    /// refuses anything else, and says why in the failure shown here.
    func apply() {
        guard let preview = previewJob else {
            phase = .failed("There is no finished preview to apply. Preview again, then apply.")
            return
        }
        guard !reviewExpired(preview) else {
            phase = .failed("This review is more than \(Int(JobStore.reviewWindow / 60)) minutes old, so it can no longer be applied. Preview again to see what would be cleaned now.")
            return
        }
        lastOutput = ""
        applyJob = jobs.apply(from: preview, approved: approvedSet)
        syncFromJobs()
    }

    // MARK: - finding the jobs again

    /// On appear and when the cleaner changes: take the store's jobs for this
    /// cleaner, so a window that was closed and reopened shows the same
    /// progress or the same result.
    func adoptCurrentJobs() {
        let kind = cleaner.jobKind
        resetRuns()
        // only what is still running, or recent and not dismissed: a review comes
        // back for fifteen minutes, never for as long as the app has been open
        previewJob = jobs.adoptable(kind: kind, intents: [.preview])
        let applied = jobs.adoptable(kind: kind, intents: [.apply])
        applyJob = newer(applied, than: previewJob) ? applied : nil
        if let shown = applyJob ?? previewJob {
            // the toggles must read what the job was started with
            if cleaner == .storageClean { storageDeep = shown.request.options.deep }
            if cleaner == .tempClean { tempPermanent = shown.request.options.permanent }
        }
        syncFromJobs()
    }

    /// Whether a finished preview is past the point where it can be applied.
    func reviewExpired(_ preview: Job?, at date: Date = Date()) -> Bool {
        guard let expiry = preview?.reviewExpiry else { return false }
        return date >= expiry
    }

    private func newer(_ job: Job?, than other: Job?) -> Bool {
        guard let job else { return false }
        guard let other else { return true }
        let order = jobs.jobs.map(\.id)
        guard let mine = order.firstIndex(of: job.id), let theirs = order.firstIndex(of: other.id) else { return true }
        return mine > theirs
    }

    // MARK: - reading a job into the screen

    /// Puts the screen in the phase its job is in, and its run on screen.
    func syncFromJobs() {
        guard let job = applyJob ?? previewJob else { return }
        switch job.state {
        case .queued, .running:
            phase = job.intent == .apply ? .applying : .previewing

        case .succeeded(let outcome):
            // A review is never built from a fallback: if the log held no block of
            // this job's own, the newest block belongs to another run.
            if job.intent == .preview, case .newestFallback = outcome.match {
                lastOutput = job.lines.joined(separator: "\n")
                phase = .failed("Couldn't find this run's results in the log, so there is nothing reliable to review. Preview again.")
                return
            }
            switch outcome.parsed {
            case .reap(let run): reapRun = run
            case .storage(let run): storageRun = run
            case .temp(let run): tempRun = run
            default: break
            }
            lastOutput = job.lines.joined(separator: "\n")
            if job.intent == .apply {
                phase = .done(doneSummary)
                Task { await loadHistory() }
            } else {
                phase = .review
            }

        case .failed(let failure):
            lastOutput = job.lines.joined(separator: "\n")
            phase = .failed(failure.message)

        case .cancelled(let partial):
            lastOutput = job.lines.joined(separator: "\n")
            if job.intent == .apply {
                phase = .failed(partial
                                ? "Stopped. Items already handled are listed in the receipts."
                                : "Stopped before anything changed.")
                Task { await loadHistory() }
            } else {
                resetToIdle()       // a preview you stopped has nothing to review
            }
        }
    }

    private var doneSummary: String {
        switch cleaner {
        case .memoryClean, .reclaim:
            let closed = reapRun?.allItems.filter { $0.status == .killed || $0.status == .quit } ?? []
            let mb = closed.compactMap(\.mb).reduce(0, +)
            return closed.isEmpty ? "Done — nothing needed closing."
                                  : "Closed \(closed.count) — freed ~\(mb) MB. Receipts in the log."
        case .storageClean:
            let freed = storageRun?.items.filter { $0.status == .deleted }
                .map(\.sizeBytes).reduce(0, +) ?? 0
            return freed == 0 ? "Done — nothing removed."
                              : "Freed \(ByteSize.format(freed)). Receipts in the log."
        case .janitor:
            let trashed = storageRun?.items.filter { $0.status == .trashed }
                .map(\.sizeBytes).reduce(0, +) ?? 0
            return trashed == 0 ? "Done — nothing needed tidying."
                                : "Moved \(ByteSize.format(trashed)) to the Trash — recoverable there."
        case .tempClean:
            let acted = tempRun?.actedBytes ?? 0
            if acted == 0 { return "Done — nothing was cleared." }
            return tempPermanent
                ? "Deleted \(ByteSize.format(acted)) permanently. Receipts in the log."
                : "Moved \(ByteSize.format(acted)) to the Trash — restore from Undo; the space returns when the Trash is emptied."
        }
    }

    // MARK: - resetting

    private func resetRuns() {
        reapRun = nil
        storageRun = nil
        tempRun = nil
        deselected.removeAll()
    }

    /// Discard, "New Preview" and "Try Again": forget this review. The jobs
    /// stay in the store and in Activity.
    func resetToIdle() {
        jobs.dismiss(previewJob)
        jobs.dismiss(applyJob)
        phase = .idle
        previewJob = nil
        applyJob = nil
        resetRuns()
    }
}

extension ActionsSettingsView.Cleaner {
    /// The job kind that runs this cleaner.
    var jobKind: JobKind {
        switch self {
        case .memoryClean: .memoryClean
        case .reclaim: .reclaim
        case .storageClean: .storageClean
        case .janitor: .janitor
        case .tempClean: .tempClean
        }
    }
}
