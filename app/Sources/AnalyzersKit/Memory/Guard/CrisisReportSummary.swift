import Foundation

/// A crisis report read as a person reads it: which apps were using the
/// memory, not a table of 25 processes. Built from the forensics parser's own
/// snapshot, so the numbers are exactly the report's.
public struct CrisisReportSummary: Sendable {

    public struct App: Identifiable, Hashable, Sendable {
        public let name: String
        public let bytes: Int64
        public let processCount: Int
        /// The coding agent whose session these belong to, when they do.
        public let agentSession: String?
        public var id: String { name }
        public var memoryText: String { MemorySize.text(bytes) }
    }

    public let path: String
    /// "2026-08-02 23:35:39" — the report's own timestamp.
    public let title: String
    public let pressure: String?
    public let swap: String?
    public let physicalMemory: String?
    /// Largest first, by app or tool (every process of one app counted once).
    public let apps: [App]
    public let processes: [ForensicsProcessRow]

    public var listedBytes: Int64 { apps.reduce(0) { $0 + $1.bytes } }

    /// "OrbStack, Node.js and Claude Code were using 21.4 GB" — the first
    /// three apps by size, and what they add up to.
    public var headline: String {
        let top = apps.prefix(3)
        guard !top.isEmpty else { return "The report lists no programs." }
        let names = top.map(\.name)
        let joined: String
        switch names.count {
        case 1: joined = names[0]
        case 2: joined = "\(names[0]) and \(names[1])"
        default: joined = "\(names[0]), \(names[1]) and \(names[2])"
        }
        let bytes = top.reduce(Int64(0)) { $0 + $1.bytes }
        return "\(joined) \(names.count == 1 ? "was" : "were") using \(MemorySize.text(bytes))."
    }

    /// Reads the report file; nil when it is gone or is not a report.
    public static func read(path: String) -> CrisisReportSummary? {
        guard let snapshot = ForensicsParser.parse(fileAt: path) else { return nil }
        return CrisisReportSummary(path: path, snapshot: snapshot)
    }

    init(path: String, snapshot: ForensicsSnapshot) {
        self.path = path
        title = snapshot.header
        pressure = snapshot.pressureLevel.map(Self.pressureWords)
        swap = snapshot.swapLine
        physicalMemory = snapshot.physMemLine
        processes = snapshot.processes

        // who each process belongs to: the same ancestry walk the guard's
        // session protection uses, over only what the report lists
        var table: [Int: (command: String, ppid: Int)] = [:]
        for row in snapshot.processes { table[row.pid] = (row.args, row.ppid) }
        let sessions = CodingAgentHosts.sessionOwners(among: table)

        var byName: [String: (bytes: Int64, count: Int, agent: String?)] = [:]
        for row in snapshot.processes {
            let name = ProcessNaming.name(forCommand: row.args)
            var entry = byName[name] ?? (0, 0, nil)
            entry.bytes += Int64(row.rssKB) * 1024
            entry.count += 1
            entry.agent = entry.agent ?? sessions[row.pid]
            byName[name] = entry
        }
        apps = byName
            .map { App(name: $0.key, bytes: $0.value.bytes, processCount: $0.value.count, agentSession: $0.value.agent) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
    }

    private static func pressureWords(_ level: Int) -> String {
        switch level {
        case ..<2: "Normal"
        case 2..<4: "High"
        default: "Critical"
        }
    }
}
