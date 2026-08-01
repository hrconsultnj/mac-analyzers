import Foundation
import AnalyzersKit

/// History aggregated from the suite's own logs — the "what has this thing
/// actually done for me" numbers. Reads the same parsers the log panes use;
/// nothing leaves the Mac.
struct TrendsSnapshot {
    struct DayCount: Identifiable {
        let day: Date
        let kills: Int
        let spikes: Int
        let other: Int
        var id: Date { day }
    }

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
    let latestReclaimableBytes: Int64
    let cleanRuns: Int
    let days: [DayCount]
    let offenders: [Offender]
    let headline: String

    var isEmpty: Bool {
        kills + spikes + pressure + cpuHogs == 0
            && memoryFreedMB == 0 && storageFreedBytes == 0 && cleanRuns == 0
    }
}

enum TrendsModel {

    enum Period: CaseIterable {
        case week, month, all

        var label: String {
            switch self {
            case .week: "7 Days"
            case .month: "30 Days"
            case .all: "All"
            }
        }

        var interval: TimeInterval {
            switch self {
            case .week: 7 * 86_400
            case .month: 30 * 86_400
            case .all: 365 * 86_400
            }
        }

        var headlinePrefix: String {
            switch self {
            case .week: "Last 7 days"
            case .month: "Last 30 days"
            case .all: "All time"
            }
        }
    }

    private static let headerDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func snapshot(period: Period) -> TrendsSnapshot {
        let cutoff = Date().addingTimeInterval(-period.interval)
        let events = GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog,
                                              within: period.interval, limit: 2000)

        var kills = 0, spikes = 0, pressure = 0, cpuHogs = 0
        var guardFreedMB = 0
        var perDay: [Date: (kills: Int, spikes: Int, other: Int)] = [:]
        var perProcess: [String: (count: Int, kills: Int)] = [:]
        let calendar = Calendar.current

        for event in events {
            let day = calendar.startOfDay(for: event.date)
            var bucket = perDay[day] ?? (0, 0, 0)
            switch event.kind {
            case .killed:
                kills += 1
                bucket.kills += 1
                guardFreedMB += event.residentMB ?? 0
            case .spike:
                spikes += 1
                bucket.spikes += 1
            case .cpuHog:
                cpuHogs += 1
                bucket.other += 1
            case .capExceeded, .pressureWarning, .pressureCritical, .warning:
                pressure += 1
                bucket.other += 1
            case .forensics:
                bucket.other += 1
            }
            perDay[day] = bucket

            if event.pid != nil {
                var entry = perProcess[event.friendlyName] ?? (0, 0)
                entry.count += 1
                if event.isKill { entry.kills += 1 }
                perProcess[event.friendlyName] = entry
            }
        }

        // memory reaps: actual closures only (dry rows are intent, not effect)
        var reapFreedMB = 0
        for kind in [LogKind.memoryClean, .reclaim] {
            for run in LogParser.runs(for: kind) {
                guard let date = runDate(run.header), date >= cutoff else { continue }
                let parsed = ReapParser.parse(runHeader: run.header, lines: run.lines)
                reapFreedMB += parsed.allItems
                    .filter { $0.status == .killed || $0.status == .quit }
                    .compactMap(\.mb).reduce(0, +)
            }
        }

        // storage: deleted bytes across real runs; latest run's identified total
        var storageFreed: Int64 = 0
        var latestReclaimable: Int64 = 0
        var cleanRuns = 0
        let storageRuns = LogParser.runs(for: .storageClean)
        for (index, run) in storageRuns.enumerated() {
            guard let date = runDate(run.header), date >= cutoff else { continue }
            cleanRuns += 1
            let parsed = StorageCleanParser.parse(runHeader: run.header, lines: run.lines)
            storageFreed += parsed.items.filter { $0.status == .deleted }
                .map(\.sizeBytes).reduce(0, +)
            if index == 0 {
                latestReclaimable = parsed.items.filter { $0.status == .dry }
                    .map(\.sizeBytes).reduce(0, +)
            }
        }

        let days = perDay.map {
            TrendsSnapshot.DayCount(day: $0.key, kills: $0.value.kills,
                                    spikes: $0.value.spikes, other: $0.value.other)
        }.sorted { $0.day < $1.day }

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
        if storageFreed > 0 { claims.append("\(ByteSize.format(storageFreed)) of disk reclaimed") }
        let headline = claims.isEmpty
            ? "\(period.headlinePrefix): all quiet — nothing needed defending."
            : "\(period.headlinePrefix): \(claims.joined(separator: ", "))."

        return TrendsSnapshot(kills: kills, spikes: spikes, pressure: pressure,
                              cpuHogs: cpuHogs, memoryFreedMB: memoryFreedMB,
                              storageFreedBytes: storageFreed,
                              latestReclaimableBytes: latestReclaimable,
                              cleanRuns: cleanRuns, days: days,
                              offenders: offenders, headline: headline)
    }

    /// Run headers open with "yyyy-MM-dd HH:mm | …" (block logs). Day-grouped
    /// logs use bare "yyyy-MM-dd" headers.
    private static func runDate(_ header: String) -> Date? {
        headerDate.date(from: String(header.prefix(16)))
            ?? headerDate.date(from: String(header.prefix(10)) + " 12:00")
    }
}
