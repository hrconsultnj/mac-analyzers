import Foundation

/// What the Welcome flow shows of THIS Mac: its own numbers on the first step, and what Memory Guard would do now.
public struct WelcomeNumbers: Sendable, Equatable {
    public var memoryTotal: Int64
    public var memoryUsed: Int64
    public var diskTotal: Int64
    public var diskUsed: Int64
    public var diskFree: Int64
    /// Items that start by themselves, from the last Login & Startup Items audit; nil when it has not run.
    public var startupItems: Int?

    @MainActor public static func read() -> WelcomeNumbers {
        let memory = MemoryBreakdown.current()
        let disk = LiveStats.diskUsage()
        return WelcomeNumbers(memoryTotal: memory?.totalBytes ?? Int64(ProcessInfo.processInfo.physicalMemory),
                              memoryUsed: memory?.usedBytes ?? 0, diskTotal: disk?.totalBytes ?? 0,
                              diskUsed: disk?.usedBytes ?? 0, diskFree: disk?.freeBytes ?? 0,
                              startupItems: StartupInventory.latest()?.items.count)
    }

    public static let fixture = WelcomeNumbers(memoryTotal: 32 << 30, memoryUsed: Int64(23.3 * Double(1 << 30)),
                                               diskTotal: 460 << 30, diskUsed: 322 << 30, diskFree: 114 << 30, startupItems: 29)
}

/// Memory Guard's preview: the kinds of thing running on this Mac, by the Monitor's categories, what the guard may do with
/// each, and what it would do right now. For now the guard only watches, so nothing here is acted on.
public struct GuardPreview: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String { kind }
        public let kind: String
        public let count: Int
        public let bytes: Int64
        /// The sentence from the list of kinds: what the guard may do.
        public let guardMay: String
        /// Over the limit now: what it would stop.
        public let wouldStop: Bool
    }
    public struct Section: Sendable, Equatable, Identifiable {
        public var id: String { title }
        public let title: String
        public let rows: [Row]
    }
    public let sections: [Section]
    public let limitBytes: Int64

    public var wouldStop: [Row] { sections.flatMap(\.rows).filter(\.wouldStop) }

    /// From the census, as the Monitor reads it. Slow (it reads every process): run it off the main actor.
    public static func read(limitMB: Int) -> GuardPreview {
        let census = MemoryCensus.take()
        let limit = Int64(limitMB) * 1_048_576
        var sections: [Section] = []
        for category in CensusGroup.Category.allCases {
            var byKind: [String: (kind: ProcessKind, count: Int, bytes: Int64, over: Bool)] = [:]
            for group in census.groups where group.category == category {
                var entry = byKind[group.kind.id] ?? (group.kind, 0, 0, false)
                entry.count += 1
                entry.bytes += group.totalBytes
                // a developer tool over the limit is what the guard would step in on
                if group.kind.devTooling, group.totalBytes > limit { entry.over = true }
                byKind[group.kind.id] = entry
            }
            let rows = byKind.values.sorted { $0.bytes > $1.bytes }.prefix(4).map {
                Row(kind: $0.kind.name, count: $0.count, bytes: $0.bytes, guardMay: $0.kind.guardMay, wouldStop: $0.over)
            }
            if !rows.isEmpty { sections.append(Section(title: category.title, rows: rows)) }
        }
        return GuardPreview(sections: sections, limitBytes: limit)
    }

    /// A long preview (four kinds in each category, the most the screen ever shows): longer than the window, so it must scroll.
    public static let fixture = GuardPreview(sections: [
        Section(title: "Apps", rows: [
            Row(kind: "Meeting & Chat", count: 2, bytes: 2_100_000_000, guardMay: "Asks to quit only when you choose; never stopped on its own.", wouldStop: false),
            Row(kind: "Browsers", count: 3, bytes: 4_800_000_000, guardMay: "Never stopped by the guard.", wouldStop: false),
            Row(kind: "Editors & IDEs", count: 2, bytes: 3_300_000_000, guardMay: "Never stopped by the guard.", wouldStop: false),
            Row(kind: "Other Apps", count: 9, bytes: 1_900_000_000, guardMay: "Never stopped by the guard.", wouldStop: false)]),
        Section(title: "Tools", rows: [
            Row(kind: "Dev Servers", count: 3, bytes: 7_200_000_000, guardMay: "May be stopped when one holds more than your limit.", wouldStop: true),
            Row(kind: "Databases", count: 1, bytes: 900_000_000, guardMay: "Watched only.", wouldStop: false),
            Row(kind: "Containers & VMs", count: 2, bytes: 2_600_000_000, guardMay: "Watched only.", wouldStop: false),
            Row(kind: "Coding-Agent Sessions", count: 4, bytes: 1_400_000_000, guardMay: "Always spared while a session is live.", wouldStop: false)]),
        Section(title: "macOS", rows: [
            Row(kind: "Background Services", count: 24, bytes: 3_000_000_000, guardMay: "Never touched.", wouldStop: false),
            Row(kind: "Terminals", count: 3, bytes: 600_000_000, guardMay: "Never stopped by the guard.", wouldStop: false)])],
        limitBytes: 6_700_000_000)
}
