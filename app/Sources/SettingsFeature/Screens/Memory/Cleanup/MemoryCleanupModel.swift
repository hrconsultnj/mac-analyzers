import SwiftUI
import AnalyzersKit

/// Memory Cleanup's state: which of the two cleanups, its options, the job
/// that is previewing or applying, and the review read back from that job.
/// Everything the engine runs goes through the job store: a preview is a
/// job, an apply is built from the finished preview with exactly what is
/// ticked, and a screen that closes and opens again finds its job again.
@MainActor @Observable
final class MemoryCleanupModel {

    /// The two cleanups: the leftovers sweep, and everything now.
    enum Scope: String, CaseIterable, Identifiable {
        case leftovers = "Leftovers"
        case everythingNow = "Everything Now"
        var id: String { rawValue }
        var kind: JobKind { self == .leftovers ? .memoryClean : .reclaim }
        var symbol: String { self == .leftovers ? "sparkles" : "bolt.fill" }
    }

    enum Phase: Equatable {
        case idle, previewing, review, applying
        case done(String)
        case failed(String)
    }

    var scope: Scope = .leftovers
    /// Leftovers: also end busy orphaned tools, not only idle ones.
    var includeBusyOrphans = false
    /// Everything Now: also ask the apps on your list to quit.
    var alsoQuit = false
    /// Rows the person unticked, kept per preview: leaving the screen and
    /// coming back inside the review window shows the same ticks, not everything
    /// ticked again. (Held here until the shared review store lands; then this
    /// is one call to it.)
    var deselected: Set<String> {
        get { previewJob.flatMap { Self.ticks[$0.id] } ?? [] }
        set { if let id = previewJob?.id { Self.ticks[id] = newValue } }
    }
    private static var ticks: [UUID: Set<String>] = [:]
    /// The review as it was read when its job finished, per job: its identities
    /// (who each pid was) are captured ONCE, then, never again on a rebuild — a
    /// pid reused since would otherwise be read as the program that was reviewed.
    private static var reviews: [UUID: CleanupReview] = [:]

    private(set) var phase: Phase = .idle
    private(set) var previewJob: Job?
    private(set) var applyJob: Job?
    /// What the review (or, after an apply, the result) shows.
    private(set) var review: CleanupReview?
    private(set) var rawOutput = ""

    // MARK: - what the options mean right now

    func options(reclaimApps: [String]) -> JobOptions {
        JobOptions(includeBusyOrphans: scope == .leftovers && includeBusyOrphans,
                   alsoQuit: scope == .everythingNow && alsoQuit ? reclaimApps : [])
    }

    var shownJob: Job? { applyJob ?? previewJob }

    /// Both jobs' stages, for `onChange`.
    var stamps: [JobStamp] { [JobStamp(previewJob), JobStamp(applyJob)] }

    func reviewExpired(_ date: Date = Date()) -> Bool {
        guard let expiry = previewJob?.reviewExpiry else { return false }
        return date >= expiry
    }

    // MARK: - ticks

    var selectedCount: Int { review?.selectedCount(deselected: deselected) ?? 0 }
    var selectedBytes: Int64 { review?.selectedBytes(deselected: deselected) ?? 0 }
    var canApply: Bool {
        guard phase == .review, !reviewExpired(), let review else { return false }
        return review.hasAction(deselected: deselected)
    }

    func selectAll() { deselected = [] }
    func selectNone() { deselected = Set(review?.approvableKeys ?? []) }

    // MARK: - starting jobs

    func preview(store: JobStore, reclaimApps: [String]) {
        store.dismiss(previewJob)
        store.dismiss(applyJob)
        reset()
        previewJob = store.enqueue(JobRequest(kind: scope.kind, intent: .preview,
                                              options: options(reclaimApps: reclaimApps)),
                                   trigger: .user)
        sync()
    }

    /// Built from the finished preview with exactly what is ticked. The store
    /// refuses anything else, and says why.
    func apply(store: JobStore) {
        guard let preview = previewJob, let review else {
            phase = .failed("There is no finished preview to apply. Preview again, then apply.")
            return
        }
        guard !reviewExpired() else {
            phase = .failed("This review is more than \(Int(JobStore.reviewWindow / 60)) minutes old, so it can no longer be applied. Preview again to see what would be cleaned now.")
            return
        }
        applyJob = store.apply(from: preview, approved: review.approvedSet(deselected: deselected))
        sync()
    }

    /// Throws the review away; it can no longer be applied.
    func discard(store: JobStore) {
        store.dismiss(previewJob)
        store.dismiss(applyJob)
        reset()
    }

    func stop() {
        shownJob?.cancel()
    }

    // MARK: - finding the jobs again

    /// On appear and when the scope changes: take the store's job for this
    /// cleanup — still running, or a finished preview that is recent and not
    /// dismissed — so a closed and reopened window shows the same progress or
    /// the same review.
    func adopt(store: JobStore) {
        let kind = scope.kind
        reset()
        previewJob = store.adoptable(kind: kind, intents: [.preview])
        let applied = store.adoptable(kind: kind, intents: [.apply])
        applyJob = newer(applied, than: previewJob, in: store) ? applied : nil
        if let shown = shownJob {
            includeBusyOrphans = shown.request.options.includeBusyOrphans
            alsoQuit = !shown.request.options.alsoQuit.isEmpty
        }
        sync()
    }

    private func newer(_ job: Job?, than other: Job?, in store: JobStore) -> Bool {
        guard let job else { return false }
        guard let other else { return true }
        let order = store.jobs.map(\.id)
        guard let mine = order.firstIndex(of: job.id), let theirs = order.firstIndex(of: other.id) else { return true }
        return mine > theirs
    }

    // MARK: - reading a job into the screen

    /// Puts the screen in the state its job is in, and the run on screen.
    func sync() {
        guard let job = shownJob else { return }
        rawOutput = job.lines.joined(separator: "\n")
        switch job.state {
        case .queued, .running:
            phase = job.intent == .apply ? .applying : .previewing
        case .succeeded(let outcome):
            // a review is never built from a fallback: when the log held no block
            // of this job's own, the newest block belongs to another run
            if job.intent == .preview, case .newestFallback = outcome.match {
                phase = .failed("Couldn't find this run's results in the log, so there is nothing reliable to review. Preview again.")
                return
            }
            if case .reap(let run) = outcome.parsed {
                if let known = Self.reviews[job.id] {
                    review = known
                } else {
                    let read = CleanupReview(run: run)
                    Self.reviews[job.id] = read
                    review = read
                }
            }
            if job.intent == .apply {
                phase = .done(Self.summary(of: review))
            } else {
                phase = .review
            }
        case .failed(let failure):
            phase = .failed(failure.message)
        case .cancelled(let partial):
            if job.intent == .apply {
                phase = .failed(partial ? "Stopped. Items already handled are listed in the receipts."
                                        : "Stopped before anything changed.")
            } else {
                reset()      // a preview you stopped has nothing to review
            }
        }
    }

    private func reset() {
        phase = .idle
        previewJob = nil
        applyJob = nil
        review = nil
        rawOutput = ""
    }

    // MARK: - words

    /// "Closed 3 programs, freeing about 480 MB."
    static func summary(of review: CleanupReview?) -> String {
        let closed = review?.candidates.filter { $0.state == .closed || $0.state == .quit } ?? []
        guard !closed.isEmpty else { return "Nothing needed closing." }
        let bytes = closed.reduce(Int64(0)) { $0 + $1.memoryBytes }
        let count = closed.reduce(0) { $0 + $1.count }
        return "Closed \(count) \(count == 1 ? "program" : "programs"), freeing about \(MemorySize.text(bytes))."
    }
}
