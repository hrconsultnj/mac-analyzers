import Foundation

/// What Stop or Quit does for a row, decided when the row is built — with the
/// identities it needs, so the action can re-check every process before it
/// signals one. `unavailable` carries the reason in a sentence.
public enum MonitorStop: Sendable {
    /// Nothing is offered on this row, and nothing needs explaining: a part of
    /// an app is quit by quitting the app.
    case none
    /// Offered nowhere, with the reason in a sentence (macOS's own, a live session's).
    case unavailable(String)
    /// An app: ask its main process to quit; the helpers leave with it.
    case quitApp(name: String, identities: [ProcessIdentity], processCount: Int, bytes: Int64, hosted: [String: Int])
    /// A tools group: the person picks which separate programs to stop.
    case choosePrograms(group: String, programs: [StopTarget])
    /// One separate program and everything it started.
    case stopProgram(StopTarget)
    /// One process.
    case stopProcess(LiveProcess, ProcessIdentity)
}

/// One line of Monitor's table. The table is a tree: an app or tool, the
/// parts of it (or, for command-line tools, its separate programs), and the
/// processes. Ids are stable across refreshes — a row is the same row on
/// every tick — which is what lets the table update values in place.
public struct MonitorRow: Identifiable, Sendable {

    public enum Kind: Sendable { case group, part, program, process }

    public let id: String
    public let kind: Kind
    public let category: CensusGroup.Category
    public var name: String
    /// What it is: an app's parts at a glance, a macOS service's job, where a
    /// program runs.
    public var detail: String
    public var memoryBytes: Int64
    /// Percent of one core; nil until two looks exist, or when the kernel will
    /// not say (other accounts' processes).
    public var cpu: Double?
    public var processCount: Int
    /// A process row's pid.
    public let pid: Int?
    public var children: [MonitorRow]
    public var stop: MonitorStop
    /// The app's icon comes from this pid.
    public let iconPID: Int?
    /// The process ended after the person opened its group: the row stays, at
    /// its last values, until the next explicit refresh (see `MonitorTree.merge`).
    public var isEnded = false
    /// Rows that appeared, and rows that ended, inside this OPEN row since the
    /// last explicit refresh — held back from the table, and counted here so
    /// the row can say so.
    public var pendingNew = 0
    public var pendingEnded = 0

    /// What it is, plus what is waiting to appear ("2 new, 1 ended — Refresh").
    public var detailText: String {
        var parts: [String] = []
        if !detail.isEmpty { parts.append(detail) }
        var held: [String] = []
        if pendingNew > 0 { held.append("\(pendingNew) new") }
        if pendingEnded > 0 { held.append("\(pendingEnded) ended") }
        if !held.isEmpty { parts.append(held.joined(separator: ", ") + " — Refresh") }
        return parts.joined(separator: " · ")
    }

    public var memoryText: String { MemorySize.text(memoryBytes) }
    public var cpuText: String { isEnded ? "Ended" : cpu.map { $0 < 0.05 ? "0%" : String(format: "%.1f%%", $0) } ?? "—" }
    public var hasChildren: Bool { !children.isEmpty }
    /// For the table's disclosure: nil on a leaf.
    public var childRows: [MonitorRow]? { children.isEmpty ? nil : children }

    /// Whether a search matches this row or anything under it.
    public func matches(_ text: String) -> Bool {
        let wanted = text.lowercased()
        return name.lowercased().contains(wanted) || detail.lowercased().contains(wanted)
            || pid.map { String($0) == wanted } == true
            || children.contains { $0.matches(wanted) }
    }

    /// The label a Stop or Quit control carries, or nil when there is none.
    public var stopVerb: String? {
        switch stop {
        case .none, .unavailable: nil
        case .quitApp: Names.Stop.quit
        case .choosePrograms, .stopProgram, .stopProcess: Names.Stop.stop
        }
    }

    /// Why the control is missing, for its tooltip.
    public var lockedReason: String? {
        if case .unavailable(let reason) = stop { reason } else { nil }
    }
}
