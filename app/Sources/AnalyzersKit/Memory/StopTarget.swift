import Foundation

/// One separate program inside a group of command-line tools: the top-level
/// process and everything it started. A group called "Node.js" is not one
/// thing — it is however many programs happen to be called that, in different
/// projects, and stopping the group must never end one you did not mean.
public struct StopTarget: Identifiable, Sendable {
    /// pid and birth, so a recycled pid is a different target.
    public let id: String
    /// nil when the process was already gone when the census looked.
    public let identity: ProcessIdentity?
    /// What it is ("TypeScript compiler", "npm task").
    public let name: String
    /// Where it runs: the project its working folder or command line names.
    public let whereItRuns: String?
    /// The coding agent whose live session this program belongs to. A locked
    /// program is listed and never stopped from here.
    public let lockedBy: String?
    /// Whether this account may stop it at all.
    public let canStop: Bool
    /// The top-level process and everything under it, largest first.
    public let members: [LiveProcess]
    /// Every member with its start time, deepest first — the order a stop signals them in.
    public let memberIdentities: [ProcessIdentity]
    /// The root is an interactive shell: a terminal session. It ignores a polite
    /// stop, so offering Stop would do nothing and say nothing.
    public let isInteractiveShell: Bool
    /// Live sessions that run anywhere below it (agent → count): a program that
    /// hosts terminals ends them all when it ends.
    public let hostedSessions: [String: Int]

    public var totalBytes: Int64 { members.reduce(0) { $0 + $1.memoryBytes } }
    public var totalText: String { MemorySize.text(totalBytes) }

    /// Can a person end it from a group stop?
    public var isStoppable: Bool { canStop && lockedBy == nil && hostedSessions.isEmpty && identity != nil && !isInteractiveShell
        && CodingAgentHosts.isAvailable }

    /// "TypeScript compiler in nutri-journey".
    public var label: String { whereItRuns.map { "\(name) in \($0)" } ?? name }

    /// Whether a PERSON may stop it from Monitor. A lock only guards what Sparehold does by itself (the guard, the
    /// cleanups, the menu-bar panel); the person may stop anything that runs as their own account, after the
    /// confirmation says why it is normally left alone (`protection`). What stays out of reach: another account's
    /// programs, one that has already gone, and a terminal session (a shell ignores a polite stop: close its window).
    public var isStoppableByPerson: Bool { personRefusal == nil }

    /// Why even a person cannot stop it from here, in a sentence; nil when they can.
    public var personRefusal: String? {
        if !canStop { return "\(label) belongs to another account, so no app of yours can stop it." }
        if identity == nil || memberIdentities.isEmpty { return "\(label) is not running any more." }
        if isInteractiveShell { return "A shell is a terminal session — close its window to end it." }
        let own = ProgramReach.selfChain()
        if members.contains(where: { own.contains(Int32($0.pid)) }) {
            return "Stopping \(label) would end Sparehold itself, or the program that started it."
        }
        return nil
    }

    /// Why Sparehold never stops it by itself, and what stopping it would cost, as one sentence for the
    /// confirmation and the row's tooltip; nil when nothing protects it.
    public var protection: String? {
        MemoryStop.protectionSentence(label: label, agent: lockedBy, hosted: hostedSessions,
                                      listAvailable: CodingAgentHosts.isAvailable)
    }

    /// The short reason for the lock's tooltip, without a capital or a full stop ("it's a live coding session").
    public var protectionWhy: String? {
        if !hostedSessions.isEmpty { return "it holds a live coding session" }
        if lockedBy != nil { return "it's a live coding session" }
        if !CodingAgentHosts.isAvailable { return "the list of coding agents could not be read" }
        return nil
    }

    /// Why it is locked, as a sentence for the sheet and the row's tooltip.
    public var lockedReason: String? {
        if !CodingAgentHosts.isAvailable { return CodingAgentHosts.unavailableSentence }
        if !hostedSessions.isEmpty {
            return "\(label) hosts \(ProgramReach.hostedText(hostedSessions)) — close them there."
        }
        if let agent = lockedBy { return "Part of a live \(agent) session — close it there." }
        if isInteractiveShell { return "A shell is a terminal session — close its window to end it." }
        return nil
    }
}

extension StopTarget {
    /// Test support: a program made from stand-in facts, for a render of Monitor's stop sheet. It names no real process
    /// (pid 1, a start time of zero), and nothing in a render signals anything.
    @_spi(TestSupport) public static func fixture(name: String, whereItRuns: String?, lockedBy: String? = nil, canStop: Bool = true,
                                                  megabytes: Int, processes: Int = 1) -> StopTarget {
        let identity = ProcessIdentity(pid: 1, birth: ProcessTree.Birth(seconds: 0, microseconds: 0))
        let members = (0..<processes).map { index in
            LiveProcess(pid: 90_000 + index, residentMB: megabytes / processes, rawName: name, kind: .devTool,
                        footprintBytes: Int64(megabytes / processes) * 1_048_576, label: nil, canQuit: canStop)
        }
        return StopTarget(id: "fixture-\(name)-\(whereItRuns ?? "")", identity: identity, name: name, whereItRuns: whereItRuns,
                          lockedBy: lockedBy, canStop: canStop, members: members, memberIdentities: [identity],
                          isInteractiveShell: false, hostedSessions: [:])
    }
}
