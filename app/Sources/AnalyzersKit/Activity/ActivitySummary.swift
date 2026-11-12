import Foundation

/// A run's result in one line ("Freed 4.2 GB"), and whether it left something
/// for a person to look at. The same words appear in Activity, the toolbar
/// status item and the finish notification, so they cannot disagree.
public struct ActivitySummary: Sendable, Hashable {
    public let text: String
    /// What to say while a preview is waiting for a decision.
    public let reviewText: String?
    /// Items a preview found and an apply could still act on. A recent preview
    /// with findings is "Needs review" until a newer run replaces it.
    public let findings: Int
    /// Disk space the run gave back. Memory is a different thing and is counted
    /// apart (`memoryBytes`), so a day's total never adds the two.
    public let freedBytes: Int64
    /// Memory the processes it closed were using, and how many it closed.
    public let memoryBytes: Int64
    public let closed: Int

    public init(_ text: String, review: String? = nil, findings: Int = 0, freedBytes: Int64 = 0,
                memoryBytes: Int64 = 0, closed: Int = 0) {
        self.text = text
        self.reviewText = review
        self.findings = findings
        self.freedBytes = freedBytes
        self.memoryBytes = memoryBytes
        self.closed = closed
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
                guard !dry.isEmpty else { return ActivitySummary("Nothing needed closing") }
                let found = "Found \(plural(dry.count, "process", "processes")) to close (~\(mb) MB)"
                return ActivitySummary("\(found) — nothing was closed",
                                       review: "\(found) — waiting for your review", findings: dry.count)
            }
            let closed = run.allItems.filter { $0.status == .killed || $0.status == .quit }
            let mb = closed.compactMap(\.mb).reduce(0, +)
            return closed.isEmpty
                ? ActivitySummary("Nothing needed closing")
                : ActivitySummary(mb > 0 ? "Closed \(closed.count) — freed ~\(mb) MB" : "Closed \(closed.count)",
                                  memoryBytes: Int64(mb) * 1_048_576, closed: closed.count)

        case .storage(let run):
            if run.dryRun {
                let dry = run.items.filter { $0.status == .dry }
                let bytes = dry.map(\.sizeBytes).reduce(0, +)
                if bytes > 0 {
                    let found = "Found \(plural(dry.count, "item", "items")), \(ByteSize.format(bytes))"
                    return ActivitySummary("\(found) — nothing was removed",
                                           review: "\(found) — waiting for your review", findings: dry.count)
                }
                // a long preview can lose its item lines to the log window; its own closing line has the totals
                if let counted = countedSummary(run.summary) {
                    return ActivitySummary("\(counted) — nothing was moved", review: "\(counted) — waiting for your review",
                                           findings: 1)
                }
                return ActivitySummary("Nothing stale to remove")
            }
            let trashed = run.items.filter { $0.status == .trashed }.map(\.sizeBytes).reduce(0, +)
            let deleted = run.items.filter { $0.status == .deleted }.map(\.sizeBytes).reduce(0, +)
            if trashed > 0 {
                return ActivitySummary("Moved \(ByteSize.format(trashed)) to the Trash", freedBytes: trashed)
            }
            if deleted > 0 { return ActivitySummary("Freed \(ByteSize.format(deleted))", freedBytes: deleted) }
            return ActivitySummary("Nothing was removed")

        case .temp(let run):
            if run.dryRun {
                let ready = run.readyItems
                guard !ready.isEmpty else { return ActivitySummary("Nothing ready to clear") }
                let found = "\(ByteSize.format(run.readyBytes)) in \(plural(ready.count, "item", "items")) is ready to clear"
                return ActivitySummary("\(found) — nothing was removed",
                                       review: "\(found) — waiting for your review", findings: ready.count)
            }
            let acted = run.actedBytes
            if acted == 0 { return ActivitySummary("Nothing was cleared") }
            return ActivitySummary(run.permanent ? "Deleted \(ByteSize.format(acted)) permanently"
                                                 : "Moved \(ByteSize.format(acted)) to the Trash",
                                   freedBytes: acted)

        case .spotlight(let run):
            if run.dryRun {
                guard run.unfencedCount > 0 else { return ActivitySummary("Every folder is already fenced") }
                let found = "\(plural(run.unfencedCount, "folder isn't", "folders aren't")) fenced from Spotlight"
                    + (run.unfencedBulkText.map { " (\($0))" } ?? "")
                return ActivitySummary("\(found) — nothing was changed",
                                       review: "\(found) — waiting for your review", findings: run.unfencedCount)
            }
            return ActivitySummary("Fences applied")

        case .loginItems(let run):
            let orphans = run.allEntries.filter { $0.verdict == .orphan || $0.verdict == .orphanSudo }
            if run.dryRun {
                guard !orphans.isEmpty else { return ActivitySummary("No leftover startup items") }
                let found = "Found \(plural(orphans.count, "leftover startup item", "leftover startup items"))"
                return ActivitySummary("\(found) — nothing was removed",
                                       review: "\(found) — waiting for your review", findings: orphans.count)
            }
            let removed = run.allEntries.filter { $0.verdict == .removed }.count
            return ActivitySummary(removed == 0 ? "Nothing was removed" : "Removed \(plural(removed, "item", "items"))")

        case .none:
            return ActivitySummary(kind.map(plainResult) ?? "Done")
        }
    }

    /// For the kinds that write a file or change the agents rather than a run log.
    private static func plainResult(_ kind: JobKind) -> String {
        switch kind {
        case .memoryReport, .storageReport: "Report written"
        case .networkSnapshot: "Snapshot taken"
        case .installAgents: "Background jobs installed"
        case .uninstallAgents: "Background jobs turned off"
        case .sudoersInstall: "Deleting snapshots allowed"
        case .eject: "Disk image ejected"
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
        case .guardLog, .persistence, .forensics, .cleanupApps, .cleanupRecordings, .tmReclaim: .none
        }
    }

    /// The result of one block of a log, for a row nobody tracked live.
    public static func of(_ run: LogRun, in log: EngineLog) -> ActivitySummary {
        // a restore's own block: it freed and found nothing; it put things back
        if RestoreBlock.isRestore(header: run.header) { return RestoreBlock.summary(run) }
        switch log {
        case .guardLog: return guardDay(run)
        case .persistence:
            let added = run.lines.filter { $0.contains("NEW persistence item") }.count
            if added > 0 { return ActivitySummary("\(plural(added, "new startup item was", "new startup items were")) added") }
            return ActivitySummary(run.lines.contains { $0.contains("BASELINE") }
                                   ? "Startup items recorded as the starting point" : "Startup items changed")
        case .forensics: return crisis(run)
        default:
            let parsed = parse(run, in: log)
            return of(parsed, kind: nil)
        }
    }

    // MARK: - event logs

    /// "Stopped 2 apps · 3 CPU alerts · 1 memory spike" for one day of guard events.
    private static func guardDay(_ run: LogRun) -> ActivitySummary {
        let events = run.lines.compactMap(GuardLogParser.parseLine)
        guard !events.isEmpty else { return ActivitySummary("\(plural(run.itemCount, "event", "events")) recorded") }
        var parts: [String] = []
        let killed = events.filter(\.isKill).count
        if killed > 0 { parts.append("stopped \(plural(killed, "app", "apps"))") }
        let cpu = events.filter { if case .cpuHog = $0.kind { true } else { false } }.count
        if cpu > 0 { parts.append("\(plural(cpu, "CPU alert", "CPU alerts"))") }
        let spikes = events.filter { if case .spike = $0.kind { true } else { false } }.count
        if spikes > 0 { parts.append("\(plural(spikes, "memory spike", "memory spikes"))") }
        let pressure = events.filter { $0.category == .pressure }.count
        if pressure > 0 { parts.append("\(plural(pressure, "pressure warning", "pressure warnings"))") }
        let reports = events.filter { $0.category == .reports }.count
        if reports > 0 { parts.append("\(plural(reports, "crisis report", "crisis reports"))") }
        guard let first = parts.first else { return ActivitySummary("\(plural(events.count, "event", "events")) recorded") }
        return ActivitySummary(([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: " · "))
    }

    /// A crisis report: how bad it was and who was using the memory.
    private static func crisis(_ run: LogRun) -> ActivitySummary {
        let snapshot = ForensicsParser.parse(text: run.lines.joined(separator: "\n"))
        let level: String
        switch snapshot.pressureLevel {
        case 4?: level = "Memory pressure was critical"
        case 2?: level = "Memory pressure was high"
        default: level = "Memory was running low"
        }
        guard let top = snapshot.processes.first else { return ActivitySummary(level) }
        return ActivitySummary("\(level) — \(top.friendlyName) was using \(top.rssText)")
    }

    // MARK: - from how a job ended

    public static func of(failure: JobFailure) -> ActivitySummary { ActivitySummary(failure.message) }

    public static func of(cancelledPartial partial: Bool) -> ActivitySummary {
        ActivitySummary(partial ? "Stopped — items already handled are in the receipts"
                                : "Stopped before anything changed")
    }

    // MARK: - words

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }

    /// "would move 6128 item(s), 2.5 GB, to the Trash" → "Found 6128 items, 2.5 GB".
    private static func countedSummary(_ line: String?) -> String? {
        guard let line,
              let match = line.firstMatch(of: /(\d+) item\(s\), ([\d.]+ [KMGT]?B)/) else { return nil }
        let count = Int(match.1) ?? 0
        return "Found \(plural(count, "item", "items")), \(match.2)"
    }
}
