import Foundation

/// The numbers behind Trends' "Disk reclaimed": what the storage cleaner
/// actually deleted over a period, from the runs in its log.
public enum TrendTotals {

    /// One cleanup run that deleted something.
    public struct DiskRun: Sendable {
        public let date: Date
        public let mode: String
        public let deletedBytes: Int64
        /// What the run's own closing line says it freed ("DONE — freed ~51.3 GB").
        public let summary: String?
    }

    /// Level 3 of the Storage category: what was deleted, by project.
    public struct DiskGroup: Identifiable, Sendable {
        public let project: String
        public let items: Int
        public let bytes: Int64
        public var id: String { project }
    }

    public struct Disk: Sendable {
        /// Deleted items grouped by the project they belonged to, biggest first.
        public let groups: [DiskGroup]
        /// Runs that started inside the period, with or without a result.
        public let runsInPeriod: Int
        public let runs: [DiskRun]
        public var freedBytes: Int64 { runs.reduce(0) { $0 + $1.deletedBytes } }
    }

    private static let headerDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// The time a run started, from its header. Block-log banners carry it
    /// after the script and mode ("storage-auto-clean.sh | mode=deep | APPLY |
    /// 2026-11-10 18:50:26 | roots=…"), so it is found wherever it sits; day
    /// logs open with a bare "yyyy-MM-dd". (Trends looked only at the start of
    /// the header, found no date on any storage run, and counted none.)
    public static func runDate(_ header: String) -> Date? {
        if let range = header.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}"#, options: .regularExpression),
           let date = headerDate.date(from: String(header[range])) {
            return date
        }
        if let range = header.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return headerDate.date(from: String(header[range]) + " 12:00")
        }
        return nil
    }

    /// `wholeFile: false` reads what the run list reads (the last 256 KB, the
    /// newest 20 runs) — the way Trends used to, and why it said "0 KB" over 30
    /// days. It exists so the probe can show the two side by side.
    public static func diskReclaimed(within interval: TimeInterval, wholeFile: Bool = true,
                                     now: Date = Date()) -> Disk {
        let cutoff = now.addingTimeInterval(-interval)
        let runs = wholeFile ? LogParser.allRuns(for: .storageClean) : LogParser.runs(for: .storageClean)
        var inPeriod = 0
        var found: [DiskRun] = []
        var perProject: [String: (items: Int, bytes: Int64)] = [:]
        for run in runs {
            guard let date = runDate(run.header), date >= cutoff else { continue }
            inPeriod += 1
            let parsed = StorageCleanParser.parse(runHeader: run.header, lines: run.lines)
            let deleted = parsed.items.filter { $0.status == .deleted }.reduce(Int64(0)) { $0 + $1.sizeBytes }
            for item in parsed.items where item.status == .deleted {
                var entry = perProject[item.project] ?? (0, 0)
                entry.items += 1
                entry.bytes += item.sizeBytes
                perProject[item.project] = entry
            }
            if deleted > 0 {
                found.append(DiskRun(date: date, mode: parsed.mode, deletedBytes: deleted, summary: parsed.summary))
            }
        }
        let groups = perProject.map { DiskGroup(project: $0.key, items: $0.value.items, bytes: $0.value.bytes) }
            .sorted { $0.bytes > $1.bytes }
        return Disk(groups: groups, runsInPeriod: inPeriod, runs: found)
    }

    /// Memory the cleaners actually closed over the period (dry rows are intent,
    /// not effect), from every run in both logs.
    public static func reapedMemoryMB(within interval: TimeInterval, now: Date = Date()) -> Int {
        reapedMemory(since: now.addingTimeInterval(-interval)).reduce(0) { $0 + $1.mb }
    }

    /// The same, run by run from a date on, each with the moment it started (what a chart buckets by).
    public static func reapedMemory(since start: Date) -> [(date: Date, mb: Int)] {
        var found: [(date: Date, mb: Int)] = []
        for log in [EngineLog.memoryClean, .reclaim] {
            for run in LogParser.allRuns(for: log) {
                guard let date = runDate(run.header), date >= start else { continue }
                let parsed = ReapParser.parse(runHeader: run.header, lines: run.lines)
                let mb = parsed.allItems.filter { $0.status == .killed || $0.status == .quit }
                    .compactMap(\.mb).reduce(0, +)
                if mb > 0 { found.append((date, mb)) }
            }
        }
        return found
    }

    /// What the storage cleaner deleted, run by run from a date on, each with the moment it started.
    public static func removedStorage(since start: Date) -> [(date: Date, bytes: Int64)] {
        var found: [(date: Date, bytes: Int64)] = []
        for run in LogParser.allRuns(for: .storageClean) {
            guard let date = runDate(run.header), date >= start else { continue }
            let parsed = StorageCleanParser.parse(runHeader: run.header, lines: run.lines)
            let bytes = parsed.items.filter { $0.status == .deleted }.reduce(Int64(0)) { $0 + $1.sizeBytes }
            found.append((date, bytes))
        }
        return found
    }

    /// What the latest storage check says a cleanup could remove: the findings of the
    /// NEWEST run, when that run was a preview. nil when the newest run was an apply
    /// (it already acted, so an older preview's numbers would describe things that are
    /// gone) or when there is no run. One source, for Overview, Trends and the report.
    public static func latestPreview() -> (items: [StoragePathItem], bytes: Int64)? {
        guard let newest = LogParser.allRuns(for: .storageClean).first else { return nil }
        let parsed = StorageCleanParser.parse(runHeader: newest.header, lines: newest.lines)
        guard parsed.dryRun else { return nil }
        let items = parsed.items.filter { $0.status == .dry }.sorted { $0.sizeBytes > $1.sizeBytes }
        return (items, items.reduce(Int64(0)) { $0 + $1.sizeBytes })
    }
}
