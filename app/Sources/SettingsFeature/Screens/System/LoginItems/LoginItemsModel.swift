import AnalyzersKit
import Foundation
import Observation

/// What the Login & Startup Items screen shows and the two jobs behind it: the
/// audit (a read-only run of the script) and the removal of leftovers (an
/// apply built from a finished audit).
@MainActor @Observable
final class LoginItemsModel {

    private(set) var inventory: StartupInventory?
    private(set) var changes: [StartupChange] = []
    private(set) var loaded = false
    /// Whether an audit may talk to System Events without asking; read silently.
    private(set) var permission: SystemEventsPermission = .undetermined

    /// The audit this screen shows: the store's own, found again by kind when
    /// the window is reopened mid-run.
    private(set) var audit: Job?
    private(set) var removal: Job?

    var items: [StartupItem] { inventory?.items ?? [] }

    /// What the script would remove (user-level leftovers) in the inventory
    /// on screen.
    var removable: [StartupItem] { inventory?.removable ?? [] }

    var isBusy: Bool { (audit?.isActive ?? false) || (removal?.isActive ?? false) }

    /// The sentence for a job that failed, if one did.
    var failure: String? { audit?.failureMessage ?? removal?.failureMessage }

    // MARK: - reading

    func reload() async {
        // a small file read: done off the main actor, not through the shared
        // query cache, so a refresh right after a job always sees the new file
        let found = await Task.detached(priority: .userInitiated) {
            (StartupInventory.latest(), StartupChangeParser.read())
        }.value
        inventory = found.0
        changes = found.1
        loaded = true
    }

    func checkPermission() async {
        permission = await SystemEventsPermission.currentOffPool()
    }

    // MARK: - jobs

    /// Takes back the store's jobs when the screen appears.
    func adopt(from store: JobStore) {
        audit = store.latest(.loginItems, intents: [.preview])
        removal = store.latest(.loginItems, intents: [.apply])
    }

    func startAudit(in store: JobStore) {
        audit = store.enqueue(JobRequest(kind: .loginItems, intent: .preview), trigger: .user)
    }

    func stop() {
        audit?.cancel()
        removal?.cancel()
    }

    /// The finished audit a removal can be built from: recent, not dismissed.
    func reviewedAudit(in store: JobStore) -> Job? {
        store.adoptable(kind: .loginItems, intents: [.preview])
    }

    /// Whether a removal may be offered: a recent finished audit exists AND the
    /// inventory on screen is the one that audit wrote (its run stamp is in the
    /// audit's own output). Any other run of the script rewrites the inventory,
    /// and a confirmation must list what the audit being applied found.
    func canRemove(in store: JobStore) -> Bool {
        guard let audit = reviewedAudit(in: store), let inventory else { return false }
        return inventory.isFromRun(printing: audit.lines)
    }

    /// Removes `scope` through the kernel, from the audit that is on screen.
    /// Returns false when there is no recent audit to build it from.
    @discardableResult
    func remove(_ scope: [StartupItem], in store: JobStore) -> Bool {
        guard canRemove(in: store), let preview = reviewedAudit(in: store), !scope.isEmpty else { return false }
        removal = store.apply(from: preview,
                              approved: StartupRemoval.approval(for: scope, removable: removable))
        return true
    }

    /// After a removal, audit again so the table shows what is left.
    func finishRemoval(in store: JobStore) {
        if let preview = audit { store.dismiss(preview) }
        startAudit(in: store)
    }
}
