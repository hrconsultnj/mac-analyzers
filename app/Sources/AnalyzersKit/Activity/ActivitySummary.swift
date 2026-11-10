import Foundation

/// A run's result in one line ("Freed 4.2 GB"), and whether it left something
/// for a person to look at. The same words appear in the Activity table, the
/// toolbar status item and the finish notification, so they cannot disagree.
public struct ActivitySummary: Sendable, Hashable {
    public let text: String
    /// Items a preview found and an apply could still act on. A preview with
    /// findings is "Needs review" until a newer run replaces it.
    public let findings: Int

    public init(_ text: String, findings: Int = 0) {
        self.text = text
        self.findings = findings
    }

    // MARK: - from a parsed run

    /// The result of a run the engine's own parser has read. `kind` only
    /// matters for runs that write no log the app parses.
    public static func of(_ parsed: JobOutcome.Parsed, kind: JobKind?) -> ActivitySummary {
        switch parsed {
        case .reap(let run):
            if run.dryRun {
                let dry = run.allItems.filter { $0.status == .dry }
                let mb = dry.compactMap(\.mb).reduce(0, +)
                return dry.isEmpty ? ActivitySummary("Nothing to close")
                                   : ActivitySummary("Would close \(dry.count) (~\(mb) MB)", findings: dry.count)
            }
            let closed = run.allItems.filter { $0.status == .killed || $0.status == .quit }
            let mb = closed.compactMap(\.mb).reduce(0, +)
            return closed.isEmpty ? ActivitySummary("Nothing needed closing")
                                  : ActivitySummary("Closed \(closed.count) — freed ~\(mb) MB")

        case .storage(let run):
            if run.dryRun {
                let bytes = run.items.filter { $0.status == .dry }.map(\.sizeBytes).reduce(0, +)
                let count = run.items.filter { $0.status == .dry }.count
                return bytes == 0 ? ActivitySummary("Nothing stale")
                                  : ActivitySummary("Would free \(ByteSize.format(bytes))", findings: count)
            }
            let trashed = run.items.filter { $0.status == .trashed }.map(\.sizeBytes).reduce(0, +)
            let deleted = run.items.filter { $0.status == .deleted }.map(\.sizeBytes).reduce(0, +)
            if trashed > 0 { return ActivitySummary("Moved \(ByteSize.format(trashed)) to the Trash") }
            if deleted > 0 { return ActivitySummary("Freed \(ByteSize.format(deleted))") }
            return ActivitySummary("Nothing removed")

        case .temp(let run):
            if run.dryRun {
                let ready = run.readyItems
                return ready.isEmpty ? ActivitySummary("Nothing ready to clear")
                                     : ActivitySummary("\(ByteSize.format(run.readyBytes)) ready to clear",
                                                       findings: ready.count)
            }
            let acted = run.actedBytes
            if acted == 0 { return ActivitySummary("Nothing cleared") }
            return ActivitySummary(run.permanent ? "Deleted \(ByteSize.format(acted)) permanently"
                                                 : "Moved \(ByteSize.format(acted)) to the Trash")

        case .spotlight(let run):
            if run.dryRun {
                return run.unfencedCount == 0
                    ? ActivitySummary("Everything is fenced")
                    : ActivitySummary("\(run.unfencedCount) unfenced"
                                      + (run.unfencedBulkText.map { " (\($0))" } ?? ""),
                                      findings: run.unfencedCount)
            }
            return ActivitySummary("Fences applied")

        case .loginItems(let run):
            let orphans = run.allEntries.filter { $0.verdict == .orphan || $0.verdict == .orphanSudo }
            if run.dryRun {
                return orphans.isEmpty ? ActivitySummary("No orphaned items")
                                       : ActivitySummary("\(orphans.count) orphaned", findings: orphans.count)
            }
            let removed = run.allEntries.filter { $0.verdict == .removed }.count
            return ActivitySummary(removed == 0 ? "Nothing removed" : "Removed \(removed)")

        case .none:
            return ActivitySummary(kind.map(plainResult) ?? "Done")
        }
    }

    /// For the kinds that write a file or change the agents rather than a run log.
    private static func plainResult(_ kind: JobKind) -> String {
        switch kind {
        case .memoryReport, .storageReport: "Report written"
        case .networkSnapshot: "Snapshot taken"
        case .installAgents: "Background agents installed"
        case .uninstallAgents: "Background agents turned off"
        case .sudoersInstall: "Allowed"
        case .eject: "Ejected"
        default: "Done"
        }
    }

    // MARK: - from the log a run lives in

    /// Which parser reads a log's runs; `.none` for the event-style logs.
    public static func parse(_ run: LogRun, in log: EngineLog) -> JobOutcome.Parsed {
        switch log {
        case .memoryClean, .reclaim: .reap(ReapParser.parse(runHeader: run.header, lines: run.lines))
        case .storageClean, .janitor: .storage(StorageCleanParser.parse(runHeader: run.header, lines: run.lines))
        case .tempSpace: .temp(TempCleanParser.parse(runHeader: run.header, lines: run.lines))
        case .spotlightAudit: .spotlight(SpotlightAuditParser.parse(runHeader: run.header, lines: run.lines))
        case .loginItems: .loginItems(LoginItemsParser.parse(runHeader: run.header, lines: run.lines))
        case .guardLog, .persistence, .forensics: .none
        }
    }

    /// The result of one block of a log, for a row nobody tracked live.
    public static func of(_ run: LogRun, in log: EngineLog) -> ActivitySummary {
        let parsed = parse(run, in: log)
        if case .none = parsed {
            // an event log's "run" is a day of lines
            let count = run.itemCount
            return ActivitySummary("\(count) line\(count == 1 ? "" : "s")")
        }
        return of(parsed, kind: nil)
    }

    // MARK: - from how a job ended

    public static func of(failure: JobFailure) -> ActivitySummary { ActivitySummary(failure.message) }

    public static func of(cancelledPartial partial: Bool) -> ActivitySummary {
        ActivitySummary(partial ? "Stopped — items already handled are in the receipts"
                                : "Stopped before anything changed")
    }
}
