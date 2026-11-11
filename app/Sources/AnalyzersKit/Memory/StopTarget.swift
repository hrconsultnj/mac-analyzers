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
