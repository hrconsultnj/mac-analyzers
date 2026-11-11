import AnalyzersKit
import Foundation
import Observation

/// The saved snapshots and the job that takes a new one.
@MainActor @Observable
final class NetworkModel {

    private(set) var snapshots: [NetworkSnapshotRun] = []
    private(set) var loaded = false
    /// Monitor's own account of what is running, so a program is named and
    /// grouped the way Monitor names and groups it.
    private(set) var census: MemoryCensus?
    /// The snapshot job this screen shows: the store's own, found again by
    /// kind when the window is reopened mid-run.
    private(set) var job: Job?
    /// An older snapshot picked from History; nil shows the newest.
    var viewingID: NetworkSnapshotRun.ID?

    var isTaking: Bool { job?.isActive ?? false }
    var failure: String? { job?.failureMessage }

    var newest: NetworkSnapshotRun? { snapshots.first }

    /// What the table shows: the picked snapshot, or the newest.
    var viewing: NetworkSnapshotRun? {
        viewingID.flatMap { id in snapshots.first { $0.id == id } } ?? newest
    }

    var isViewingOlder: Bool { viewing != nil && viewing?.id != newest?.id }

    func rows() -> [NetworkProcessRow] {
        guard let viewing else { return [] }
        return viewing.rows(resolving: !isViewingOlder, census: census)
    }

    func adopt(from store: JobStore) { job = store.latest(.networkSnapshot, intents: [.run]) }

    func take(in store: JobStore) {
        viewingID = nil
        job = store.enqueue(JobRequest(kind: .networkSnapshot, intent: .run), trigger: .user)
    }

    func stop() { job?.cancel() }

    func reload() async {
        let read = await Task.detached(priority: .userInitiated) {
            (NetworkSnapshotHistory.read(), MemoryCensus.take())
        }.value
        snapshots = read.0
        census = read.1
        loaded = true
    }
}
