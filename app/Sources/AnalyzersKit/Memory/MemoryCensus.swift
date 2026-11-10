import Foundation

/// The whole process table, accounted for: no size floor, no row cap. A
/// process too small to notice still lands in a group, and the groups add up
/// to everything that is running.
///
/// This file is the front door only. How a census is taken lives next to it,
/// one job per file:
///   CensusBuilder.swift                 read every process and its memory
///   CensusBuilder+Ownership.swift       which app/tool each process belongs to
///   CensusBuilder+Classification.swift  what kind of thing it is, and its name
///   CensusBuilder+Grouping.swift        fold processes into groups and parts
///   ProcessRole.swift                   what a helper process does
///   PrivilegedFootprints.swift          sizes of macOS-owned processes
///   Responsibility.swift                macOS's "works on behalf of" record
///   MemoryBreakdown.swift               where physical memory is, system-wide
public struct MemoryCensus: Sendable {

    public let breakdown: MemoryBreakdown?
    /// Largest first.
    public let groups: [CensusGroup]
    /// Processes macOS would not report a size for (shown, counted as zero).
    public let unmeasuredCount: Int

    public var processCount: Int { groups.reduce(0) { $0 + $1.members.count } }
    public var totalBytes: Int64 { groups.reduce(0) { $0 + $1.totalBytes } }

    public func groups(in category: CensusGroup.Category?) -> [CensusGroup] {
        guard let category else { return groups }
        return groups.filter { $0.category == category }
    }

    public func processCount(in category: CensusGroup.Category?) -> Int {
        groups(in: category).reduce(0) { $0 + $1.members.count }
    }

    public func totalBytes(in category: CensusGroup.Category?) -> Int64 {
        groups(in: category).reduce(0) { $0 + $1.totalBytes }
    }

    /// Blocking (reads ~1,000 processes, may run one system tool) — call it
    /// through the load coordinator, never on the main thread.
    public static func take() -> MemoryCensus {
        let builder = CensusBuilder()
        return MemoryCensus(breakdown: MemoryBreakdown.current(),
                            groups: builder.groups(),
                            unmeasuredCount: builder.unmeasuredCount)
    }
}
