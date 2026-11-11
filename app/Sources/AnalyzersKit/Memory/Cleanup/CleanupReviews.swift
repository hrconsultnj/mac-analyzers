import Foundation

/// The review of each finished memory-cleanup preview, read ONCE when the preview finishes.
///
/// A review records who each program was (its pid and the moment the kernel says it started), and an apply
/// sends exactly that. If the review were built when a screen first looked at the job, a person who was
/// elsewhere when the preview finished would get identities taken up to fifteen minutes later, and a pid
/// reused in between would be recorded as the program that was reviewed. The job store hands the finished
/// preview to `capture` the moment it is concluded, so the identities are the ones at that moment; a screen
/// asks `review(for:run:)` and never rebuilds one.
@MainActor
public enum CleanupReviews {
    private static var held: [UUID: CleanupReview] = [:]
    private static var order: [UUID] = []
    private static let keep = 20

    public static func capture(jobID: UUID, run: ReapRun) {
        guard held[jobID] == nil else { return }
        held[jobID] = CleanupReview(run: run)
        order.append(jobID)
        while order.count > keep { held[order.removeFirst()] = nil }
    }

    /// The review captured when the job finished; one is built now only for a job this process did not see
    /// finish (adopted from the ledger).
    public static func review(for jobID: UUID, run: ReapRun) -> CleanupReview {
        if let known = held[jobID] { return known }
        capture(jobID: jobID, run: run)
        return held[jobID] ?? CleanupReview(run: run)
    }
}
