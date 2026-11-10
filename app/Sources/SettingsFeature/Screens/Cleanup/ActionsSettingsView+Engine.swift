import SwiftUI
import AnalyzersKit
import UIComponents

/// Talking to the engine: preview, apply, reading the latest run back, and
/// resetting the screen.
extension ActionsSettingsView {

    func preview() async {
        guard FileManager.default.isExecutableFile(atPath: cleaner.script.path) else {
            phase = .failed("The cleaning tools aren't installed on this Mac (expected \(cleaner.script.path)).")
            return
        }
        phase = .previewing
        let result = await ActionRunner.run(script: cleaner.script, args: ["--dry-run"] + modeArgs)
        guard result.exitCode == 0 else {
            lastOutput = result.output
            phase = .failed(ExitExplanation.explain(exitCode: result.exitCode, verb: "preview"))
            return
        }
        lastOutput = result.output
        parseLatestRun()
        phase = .review
    }

    func apply() async {
        phase = .applying
        let result = await ActionRunner.run(script: cleaner.script,
                                            args: ["--apply"] + modeArgs + approvalArgs())
        lastOutput = result.output
        guard result.exitCode == 0 else {
            phase = .failed(ExitExplanation.explain(exitCode: result.exitCode, verb: "apply"))
            return
        }
        parseLatestRun()
        phase = .done(doneSummary)
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

    private func parseLatestRun() {
        guard let latest = LogParser.runs(for: cleaner.logKind).first else {
            reapRun = nil
            storageRun = nil
            tempRun = nil
            return
        }
        switch cleaner {
        case .memoryClean, .reclaim:
            reapRun = ReapParser.parse(runHeader: latest.header, lines: latest.lines)
        case .storageClean, .janitor:
            storageRun = StorageCleanParser.parse(runHeader: latest.header, lines: latest.lines)
        case .tempClean:
            tempRun = TempCleanParser.parse(runHeader: latest.header, lines: latest.lines)
        }
    }

    func resetToIdle() {
        phase = .idle
        reapRun = nil
        storageRun = nil
        tempRun = nil
        deselected.removeAll()
    }
}
