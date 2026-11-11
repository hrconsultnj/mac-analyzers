import Foundation

/// A process, for good: its pid and the moment the kernel recorded it as
/// started. A pid names a process only while it lives — pids are recycled —
/// so anything that is about to act on a process (a stop, a quit) carries
/// this and re-checks it first (`ProcessTree.signalIfSame`).
public struct ProcessIdentity: Hashable, Sendable {
    public let pid: Int
    public let birth: ProcessTree.Birth

    public init(pid: Int, birth: ProcessTree.Birth) {
        self.pid = pid
        self.birth = birth
    }

    /// The live process's identity, or nil when it is not running.
    public static func of(pid: Int) -> ProcessIdentity? {
        guard pid > 1, pid <= Int(Int32.max), let birth = ProcessTree.Birth.of(Int32(pid)) else { return nil }
        return ProcessIdentity(pid: pid, birth: birth)
    }

    /// Whether this pid is still the process that was seen.
    public var isStillRunning: Bool { ProcessTree.Birth.of(Int32(pid)) == birth }
}
