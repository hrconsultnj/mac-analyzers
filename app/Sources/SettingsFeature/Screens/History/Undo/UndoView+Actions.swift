import AppKit
import SwiftUI
import AnalyzersKit

/// Loading the history, restoring items, copying a stopped server's command.
extension UndoView {

    func load() async {
        await awaitLoad({ UndoHistory.entries() }) {
            entries = $0
            loaded = true
            // open what can still be put back, and the guard's days, the first time this screen shows rows
            let wanted = UndoNode.tree($0).flatMap { $0.children ?? [] }.filter {
                if case .run(let run) = $0.kind { return run.restorable > 0 || run.isGuard }
                return false
            }
            open.seedIfUntouched(Set(wanted.map(\.id)))
            rebuild()
        }
    }

    func restoreAll(_ run: UndoRun) {
        restore(run.entries.filter(\.isRestorable))
    }

    /// Moves each item back out of the Trash, off the main thread (the buttons are disabled
    /// while it runs). This is an app-side file move, not an engine script, so it is not a
    /// job; one Restore click writes ONE block in each cleaner's log (Activity lists it as
    /// its own row, "Restored 3 Items"). `UndoLedger.restore` re-checks that the item in the
    /// Trash is the one the cleaner put there at this moment; anything it refuses, or a block
    /// it could not write, is said in an alert.
    func restore(_ items: [UndoEntry]) {
        guard !restoring else { return }
        restoring = true
        let wanted = items.compactMap { entry -> (title: String, item: TrashedItem)? in
            guard case .trashed(let item) = entry.source else { return nil }
            return (entry.title, item)
        }
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                UndoLedger.restore(wanted.map(\.item), titles: wanted.map(\.title))
            }.value
            var messages = outcome.failures.prefix(3).map { "\($0.title): \($0.message)" }
            if outcome.failures.count > 3 { messages.append("and \(outcome.failures.count - 3) more.") }
            if outcome.unrecorded > 0 {
                messages.append("\(outcome.unrecorded) item\(outcome.unrecorded == 1 ? " was" : "s were") put back, but the cleanup log could not be written to, so the list may still show them.")
            }
            restoreError = messages.isEmpty ? nil : messages.joined(separator: "\n")
            await LoadCoordinator.shared.invalidateAll()
            await load()
            restoring = false
        }
    }

    func copy(_ event: GuardEvent) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(event.processName, forType: .string)
        copiedID = event.id
    }
}
