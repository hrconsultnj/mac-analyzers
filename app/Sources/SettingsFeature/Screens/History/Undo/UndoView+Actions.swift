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

    /// Moves each item back out of the Trash, off the main thread, one restore at
    /// a time (the buttons are disabled while it runs). This is an app-side file
    /// move with its own `[RESTORED]` receipt, not an engine script, so it is not
    /// a job. `UndoLedger.restore` re-checks that the item in the Trash is the one
    /// the cleaner put there at this moment; anything it refuses, or any receipt
    /// it could not write, is said in an alert.
    func restore(_ items: [UndoEntry]) {
        guard !restoring else { return }
        restoring = true
        let wanted = items.compactMap { entry -> (title: String, item: TrashedItem)? in
            guard case .trashed(let item) = entry.source else { return nil }
            return (entry.title, item)
        }
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (failed: [String], unrecorded: Int) in
                var failed: [String] = []
                var unrecorded = 0
                for (title, item) in wanted {
                    do {
                        if try !UndoLedger.restore(item).receiptWritten { unrecorded += 1 }
                    } catch {
                        failed.append("\(title): \(error.localizedDescription)")
                    }
                }
                return (failed, unrecorded)
            }.value
            var messages = outcome.failed.prefix(3).map { $0 }
            if outcome.failed.count > 3 { messages.append("and \(outcome.failed.count - 3) more.") }
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
