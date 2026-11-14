import Foundation
import AnalyzersKit

/// History aggregated from the suite's own logs — the "what has this thing
/// actually done for me" numbers. Reads the same parsers the log panes use;
/// nothing leaves the Mac.
struct TrendsSnapshot {
    struct Offender: Identifiable {
        let name: String
        let count: Int
        let kills: Int
        var id: String { name }
    }

    let kills: Int
    let spikes: Int
    let pressure: Int
    let cpuHogs: Int
    let memoryFreedMB: Int
    let storageFreedBytes: Int64
    /// nil when the newest storage run was an apply: nothing is waiting to be reclaimed.
    let latestReclaimableBytes: Int64?
    let cleanRuns: Int
    /// The period these numbers are for: the screen keeps showing the previous snapshot while the next one loads.
    let period: ReportPeriod
    /// One bar per hour (the last 24 hours) or per day, oldest first.
    let buckets: [TrendBucket]
    let offenders: [Offender]
    let headline: String

    var isEmpty: Bool {
        kills + spikes + pressure + cpuHogs == 0
            && memoryFreedMB == 0 && storageFreedBytes == 0 && cleanRuns == 0
    }
}

/// One process's share of the window's freed memory — guard kills' resident
/// size plus reap runs' actual closures, combined.
struct MemoryFreedEntry: Identifiable {
    let name: String
    let freedMB: Int
    var id: String { name }
}

/// One thing a cleanup removed, named the way the Storage screens name it (`StorageNaming`).
struct RemovedItem: Identifiable {
    let id: String
    let title: String
    let sizeBytes: Int64
}

/// Deleted storage items in the window for one project (or app, or tool: what `StorageNaming` groups them under),
/// sized and sorted.
struct DiskReclaimedGroup: Identifiable {
    let project: String
    let items: [RemovedItem]
    let totalBytes: Int64
    var id: String { project }
}

/// What the latest check found it could reclaim, one row per thing, named and grouped by `StorageNaming`.
struct ReclaimableItem: Identifiable {
    let id: String
    let title: String
    let group: String
    let sizeBytes: Int64
}

/// One process's full guard timeline in the window, plus the header stats
/// the offender drill-down leads with.
struct OffenderTimeline {
    let events: [GuardEvent]
    let eventCount: Int
    let killCount: Int
    let peakResidentMB: Int
}

enum TrendsModel {

    static func snapshot(period: ReportPeriod, now: Date = Date()) -> TrendsSnapshot {
        let start = period.start(now: now)
        let events = GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog, since: start)

        var kills = 0, spikes = 0, pressure = 0, cpuHogs = 0
        var guardFreedMB = 0
        var perProcess: [String: (count: Int, kills: Int)] = [:]

        for event in events {
            switch event.kind {
            case .killed:
                kills += 1
                guardFreedMB += event.residentMB ?? 0
            case .spike:
                spikes += 1
            case .cpuHog:
                cpuHogs += 1
            case .capExceeded, .pressureWarning, .pressureCritical, .warning:
                pressure += 1
            case .forensics, .stopFailed:   // a stop that found the process already gone is not a kill
                break
            }
            if event.pid != nil {
                var entry = perProcess[event.displayName] ?? (0, 0)
                entry.count += 1
                if event.isKill { entry.kills += 1 }
                perProcess[event.displayName] = entry
            }
        }

        // memory reaps: actual closures only (dry rows are intent, not effect); storage: deleted bytes across real runs
        let reaped = TrendTotals.reapedMemory(since: start)
        let removed = TrendTotals.removedStorage(since: start)
        let reapFreedMB = reaped.reduce(0) { $0 + $1.mb }
        let storageFreed = removed.reduce(Int64(0)) { $0 + $1.bytes }
        let cleanRuns = removed.count

        let buckets = TrendBuckets.make(period: period, now: now, events: events,
                                        freed: reaped, removed: removed)

        let offenders = perProcess.map {
            TrendsSnapshot.Offender(name: $0.key, count: $0.value.count, kills: $0.value.kills)
        }.sorted { ($0.count, $0.kills) > ($1.count, $1.kills) }
            .prefix(6).map { $0 }

        let memoryFreedMB = guardFreedMB + reapFreedMB
        var claims: [String] = []
        if kills > 0 { claims.append("\(kills) runaway\(kills == 1 ? "" : "s") stopped") }
        if spikes > 0 { claims.append("\(spikes) spike\(spikes == 1 ? "" : "s") caught") }
        if memoryFreedMB > 0 {
            claims.append("\(String(format: "%.1f", Double(memoryFreedMB) / 1024)) GB of memory freed")
        }
        if storageFreed > 0 { claims.append("\(ByteSize.format(storageFreed)) removed from disk by cleanups") }
        let headline = claims.isEmpty
            ? "\(period.title): all quiet — nothing needed defending."
            : "\(period.title): \(claims.joined(separator: ", "))."

        return TrendsSnapshot(kills: kills, spikes: spikes, pressure: pressure,
                              cpuHogs: cpuHogs, memoryFreedMB: memoryFreedMB,
                              storageFreedBytes: storageFreed,
                              latestReclaimableBytes: TrendTotals.latestPreview()?.bytes,
                              cleanRuns: cleanRuns, period: period, buckets: buckets,
                              offenders: offenders, headline: headline)
    }

    /// Guard events scoped to `period` and filtered to one category — the
    /// drill-down list behind each Defended tile.
    static func events(period: ReportPeriod, category: GuardEvent.Category) -> [GuardEvent] {
        GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog, since: period.start())
            .filter { $0.category == category }
    }

    /// Per-process memory recovered in the window: guard kills' resident size
    /// plus reap runs' actual closures (KILLED/QUIT — dry rows are intent,
    /// not effect, same rule as snapshot()).
    static func memoryFreedByProcess(period: ReportPeriod) -> [MemoryFreedEntry] {
        let cutoff = period.start()
        var perProcess: [String: Int] = [:]

        for event in GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog, since: cutoff)
        where event.isKill {
            perProcess[freedName(event.displayName), default: 0] += event.residentMB ?? 0
        }
        for kind in [LogKind.memoryClean, .reclaim] {
            for run in LogParser.allRuns(for: kind) {
                guard let date = runDate(run.header), date >= cutoff else { continue }
                let parsed = ReapParser.parse(runHeader: run.header, lines: run.lines)
                for item in parsed.allItems where item.status == .killed || item.status == .quit {
                    perProcess[freedName(item.friendlyName), default: 0] += item.mb ?? 0
                }
            }
        }
        return perProcess.map { MemoryFreedEntry(name: $0.key, freedMB: $0.value) }
            .sorted { $0.freedMB > $1.freedMB }
    }

    /// What a cleanup called the thing it closed, as a name a person would use: the engine's
    /// own description ("idle-simulator (idle 21m of 20m): iPhone 18 Pro",
    /// "supabase:nutri-journey 11 containers owners=…") says how it was chosen, not what it is.
    static func freedName(_ raw: String) -> String {
        var name = raw
        if let paren = name.range(of: " (") { name = String(name[..<paren.lowerBound]) }
        if let colon = name.firstIndex(of: ":") { name = String(name[..<colon]) }
        name = name.trimmingCharacters(in: .whitespaces)
        let words: [String: String] = ["idle-simulator": "iOS Simulator", "idle-metro": "Metro bundler",
                                       "supabase": "Supabase local database"]
        if let known = words[name.lowercased()] { return known }
        if name.lowercased().hasPrefix("idle-") {
            let rest = name.dropFirst(5)
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return name.isEmpty ? raw : name
    }

    /// Deleted storage items across real runs in the window, grouped by
    /// project and sorted by size — the receipts behind "Disk reclaimed."
    static func diskReclaimedByProject(period: ReportPeriod) -> [DiskReclaimedGroup] {
        let cutoff = period.start()
        var deleted: [StoragePathItem] = []
        for run in LogParser.allRuns(for: .storageClean) {
            guard let date = runDate(run.header), date >= cutoff else { continue }
            let parsed = StorageCleanParser.parse(runHeader: run.header, lines: run.lines)
            deleted.append(contentsOf: parsed.items.filter { $0.status == .deleted })
        }
        let named = deleted.map { (name: StorageNaming.name(forPath: $0.path), item: $0) }
        return Dictionary(grouping: named, by: { $0.name.group }).map { group, members in
            let items = members.map { RemovedItem(id: $0.item.id, title: $0.name.title, sizeBytes: $0.item.sizeBytes) }
            return DiskReclaimedGroup(project: group,
                                      items: items.sorted { $0.sizeBytes > $1.sizeBytes },
                                      totalBytes: items.reduce(Int64(0)) { $0 + $1.sizeBytes })
        }.sorted { $0.totalBytes > $1.totalBytes }
    }

    /// The latest storage run's dry-run findings — "reclaimable right now"
    /// is always the most recent scan, independent of the selected period.
    static func reclaimableNow() -> [ReclaimableItem] {
        (TrendTotals.latestPreview()?.items ?? []).map {
            let name = StorageNaming.name(forPath: $0.path)
            return ReclaimableItem(id: $0.id, title: name.title, group: name.group, sizeBytes: $0.sizeBytes)
        }
    }

    /// One process's full guard timeline in the window, across every event
    /// kind, plus the stat row the offender drill-down leads with.
    static func offenderTimeline(name: String, period: ReportPeriod) -> OffenderTimeline {
        let events = GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog, since: period.start())
            .filter { $0.displayName == name }
        return OffenderTimeline(events: events,
                                eventCount: events.count,
                                killCount: events.filter(\.isKill).count,
                                peakResidentMB: events.compactMap(\.residentMB).max() ?? 0)
    }

    /// A run's start time, from its header (see `TrendTotals.runDate`).
    private static func runDate(_ header: String) -> Date? { TrendTotals.runDate(header) }
}
