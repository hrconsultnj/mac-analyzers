import Foundation

extension MemoryCensus {

    /// One process the census asked "is this developer tooling?" about, with what the rules were given.
    public struct KindRow: Sendable {
        public let pid: Int
        public let command: String
        public let subject: ProcessSubject
    }

    /// Every process, as one recorded table's row: pid, parent, resident KB, the category the census gave it, and its command
    /// line (the kernel's path where none could be read). For `agent-runner --compare-legacy --real`, which only reads it.
    @_spi(TestSupport)
    public static func realTable() -> [(pid: Int, ppid: Int, rssKB: Int, category: CensusGroup.Category, command: String)] {
        let builder = CensusBuilder()
        var category: [Int: CensusGroup.Category] = [:]
        for group in builder.groups() { for member in group.members { category[member.pid] = group.category } }
        return builder.table.values.map { entry in
            (entry.pid, entry.ppid, entry.residentMB * 1024, category[entry.pid] ?? .system, builder.argv(entry) ?? entry.path)
        }.sorted { $0.pid < $1.pid }
    }

    /// Every process the census reads a command line for (the user's own, outside macOS's folders), as the
    /// census hands it to the kinds — for the probe that compares them with the guard's old pattern.
    @_spi(TestSupport)
    public static func kindRows() -> (rows: [KindRow], environment: KindEnvironment) {
        let builder = CensusBuilder()
        let rows = builder.table.values.compactMap { entry -> KindRow? in
            guard let command = builder.argv(entry) else { return nil }
            return KindRow(pid: entry.pid, command: command, subject: builder.subject(of: entry, command: command))
        }
        .sorted { $0.pid < $1.pid }
        return (rows, builder.kindEnvironment)
    }
}
