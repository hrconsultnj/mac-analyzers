import Foundation

extension MemoryCensus {

    /// One process the census asked "is this developer tooling?" about, with what the rules were given.
    public struct KindRow: Sendable {
        public let pid: Int
        public let command: String
        public let subject: ProcessSubject
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
