import Foundation

/// What Stop or Quit does for a row, decided when the row is built — with the
/// identities it needs, so the action can re-check every process before it
/// signals one. `unavailable` carries the reason in a sentence.
public enum MonitorStop: Sendable {
    /// Nothing is offered on this row, and nothing needs explaining: a part of
    /// an app is quit by quitting the app.
    case none
    /// Offered nowhere, with the reason in a sentence: macOS's own, another account's, a terminal session.
    /// Never "protected": what only the automatic stops leave alone is still offered to the person.
    case unavailable(String)
    /// An app: ask its main process to quit; the helpers leave with it. `protection` says why Sparehold never quits it
    /// by itself, when it does not: the confirmation leads with it.
    case quitApp(name: String, identities: [ProcessIdentity], processCount: Int, bytes: Int64, hosted: [String: Int],
                 protection: String?)
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
/// every tick — which is what lets the table update values in place and keep
/// scroll position, selection and what is open.
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
    /// What a group row IS (a browser, a dev server, a macOS service); nil on rows below a group.
    public var processKind: ProcessKind?
    /// Why the group is left alone or handled with care, in words (macOS, another account, a live coding session,
    /// a Connection Tool); nil when nothing is held back. Says only what Monitor's Stop and Quit do.
    public var leftAlone: String?
    /// Why Sparehold never stops this by itself (a live coding session, the Never Close list, an app in front, a
    /// Connection Tool), and what stopping it costs, in words; nil when nothing protects it. A lock guards only the
    /// automatic stops: a row that has this still offers Stop or Quit, and the confirmation says it first.
    public var protection: String?
    /// The same, short, for the lock's tooltip: "it's a live coding session".
    public var protectionWhy: String?
    /// Whether the process this row stands for has ended since the last refresh. Rows of ended processes
    /// leave the table at the next refresh; in the moment between, the row says so instead of offering a
    /// Stop (and a Stop re-checks the process's start time regardless).
    public var isEnded: Bool {
        switch stop {
        case .stopProcess(_, let identity): !identity.isStillRunning
        case .stopProgram(let program): program.identity.map { !$0.isStillRunning } ?? false
        default: false
        }
    }

    public var memoryText: String { MemorySize.text(memoryBytes) }
    public var cpuText: String { isEnded ? "Ended" : cpu.map { $0 < 0.05 ? "0%" : String(format: "%.1f%%", $0) } ?? "—" }
    public var hasChildren: Bool { !children.isEmpty }
    /// For the table's disclosure: nil on a leaf.
    public var childRows: [MonitorRow]? { children.isEmpty ? nil : children }

    /// The same row under another id, name and pid, without children: what a process that starts inside a group
    /// looks like (the headless probe uses it to make one).
    public func copy(id: String, name: String, pid: Int) -> MonitorRow {
        MonitorRow(id: id, kind: kind, category: category, name: name, detail: detail, memoryBytes: memoryBytes,
                   cpu: cpu, processCount: 1, pid: pid, children: [], stop: .none, iconPID: nil)
    }

    /// Whether a search matches this row or anything under it.
    public func matches(_ text: String) -> Bool {
        let wanted = text.lowercased()
        return name.lowercased().contains(wanted) || detail.lowercased().contains(wanted)
            || pid.map { String($0) == wanted } == true
            || children.contains { $0.matches(wanted) }
    }

    /// The lock's tooltip, as proper sentences: why, and that the person can still do it. `protectionWhy` is either a
    /// clause ("it's a live coding session") or a whole sentence ("You asked that Safari never be closed.").
    public var lockTip: String? {
        guard let why = protectionWhy, let verb = stopVerb else { return nil }
        let quits = verb == Names.Stop.quit
        let never = "Memory Guard never \(quits ? "quits" : "stops") this by itself"
        let can = "You can still \(verb.lowercased()) it."
        return why.hasSuffix(".") ? "\(never). \(why) \(can)" : "\(never): \(why). \(can)"
    }

    /// The label a Stop or Quit control carries, or nil when there is none.
    public var stopVerb: String? {
        switch stop {
        case .none, .unavailable: nil
        case .quitApp: Names.Stop.quit
        case .choosePrograms, .stopProgram, .stopProcess: Names.Stop.stop
        }
    }

    /// Why the control is missing, for its tooltip: only what no one of this account can stop.
    public var lockedReason: String? {
        if case .unavailable(let reason) = stop { reason } else { nil }
    }
}

extension MonitorRow {
    /// Test support: a protected program's row from stand-in facts, for a render of the lock cell.
    @_spi(TestSupport) public static func fixtureProtected(name: String) -> MonitorRow {
        let target = StopTarget.fixture(name: name, whereItRuns: nil, lockedBy: "Claude Code", megabytes: 400)
        return MonitorRow(id: "fixture", kind: .program, category: .tools, name: name, detail: "live Claude Code session",
                          memoryBytes: 400 * 1_048_576, cpu: nil, processCount: 1, pid: nil, children: [],
                          stop: .stopProgram(target), iconPID: nil, protection: target.protection,
                          protectionWhy: target.protectionWhy)
    }
}
