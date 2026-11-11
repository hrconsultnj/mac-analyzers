import Darwin
import Foundation

/// Stopping a job means stopping everything it started. Terminating only the
/// bash that runs an engine script leaves its `find`, `du` and `awk` children
/// running (cooperative cancel never reaches a subprocess), so cancel walks the
/// whole descendant tree: leaf-first SIGTERM, then SIGKILL for whatever is
/// still there after the grace period.
public enum ProcessTree {

    /// How long a job gets to wind down before SIGKILL.
    public static let defaultGrace: Duration = .seconds(5)

    /// Every descendant of `root`, deepest first, so a parent is never signalled
    /// before the children it would otherwise leave behind. `root` is excluded.
    public static func descendants(of root: Int32, among pids: [Int32] = ProcTable.allPIDs()) -> [Int32] {
        var children: [Int32: [Int32]] = [:]
        for pid in pids where pid > 1 {
            children[Int32(ProcTable.parentPID(of: pid)), default: []].append(pid)
        }
        var ordered: [Int32] = []
        var seen: Set<Int32> = [root]
        var frontier: [Int32] = [root]
        while !frontier.isEmpty {
            var next: [Int32] = []
            for parent in frontier {
                for child in children[parent] ?? [] where seen.insert(child).inserted {
                    ordered.append(child)
                    next.append(child)
                }
            }
            frontier = next
        }
        return ordered.reversed()
    }

    /// When a process was born, to the microsecond the kernel records it.
    /// A pid names a process only while it lives; the pid plus this value
    /// names it for good, because a recycled pid is a new process with a new
    /// start time.
    public struct Birth: Hashable, Sendable {
        public let seconds: Int
        public let microseconds: Int

        public init(seconds: Int, microseconds: Int) {
            self.seconds = seconds
            self.microseconds = microseconds
        }

        /// The live process's birth, or nil when `pid` is not running.
        public static func of(_ pid: Int32) -> Birth? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0,
                  size >= MemoryLayout<kinfo_proc>.stride,
                  info.kp_proc.p_pid == pid else { return nil }
            let start = info.kp_proc.p_starttime
            return Birth(seconds: Int(start.tv_sec), microseconds: Int(start.tv_usec))
        }
    }

    /// Leaf-first SIGTERM of the tree under `root` (and `root` itself, last),
    /// then SIGKILL of anything still alive once `grace` has passed.
    ///
    /// While waiting, the tree is re-walked: a script that was between two
    /// commands when its first child died starts the next one, and that one
    /// gets the same treatment. Every process ever seen is remembered WITH its
    /// birth, because a child whose parent already died is re-parented to
    /// launchd and is no longer found by walking from `root` — and because a
    /// pid freed during the grace period can be handed to an unrelated
    /// process, which must never receive the SIGKILL meant for the old one.
    public static func terminate(root: Int32, grace: Duration = defaultGrace) async {
        guard root > 1, let rootBirth = Birth.of(root) else { return }
        var known: [Int32: Birth] = [root: rootBirth]
        func remember(_ pids: [Int32]) -> [Int32] {
            var fresh: [Int32] = []
            for pid in pids where known[pid] == nil {
                guard let birth = Birth.of(pid) else { continue }   // already gone
                known[pid] = birth
                fresh.append(pid)
            }
            return fresh
        }
        let first = remember(descendants(of: root))
        signal(first + [root], SIGTERM, known: known)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: grace)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            if isAlive(root, birth: rootBirth) {
                let late = remember(descendants(of: root))
                if !late.isEmpty { signal(late, SIGTERM, known: known) }
            }
            if !known.contains(where: { isAlive($0.key, birth: $0.value) }) { return }
        }
        let survivors = known.filter { isAlive($0.key, birth: $0.value) }.keys.sorted(by: >)
        signal(survivors, SIGKILL, known: known)
    }

    /// Pids of `root`'s descendants that are still alive — what a cancel
    /// check ("did it leave children behind?") looks at.
    public static func livingDescendants(of root: Int32) -> [Int32] {
        descendants(of: root).filter { isAlive($0, birth: nil) }
    }

    /// Sends `signal` to `pid` only if it is still the process that was seen
    /// with birth `expected`. Returns whether the signal was sent. `live`
    /// is how the current birth is read; tests replace it to simulate a pid
    /// that was recycled.
    ///
    /// Residual race: between the comparison and `kill` there is a window of a
    /// few microseconds in which the process could exit and its pid be reused.
    /// Closing it needs a pid file descriptor, which macOS does not offer; the
    /// start-time check turns "any recycled pid in the grace period" (seconds)
    /// into "a recycle inside two adjacent calls", and the uid check below
    /// keeps even that from reaching another user's process.
    @discardableResult
    public static func signalIfSame(pid: Int32, expected: Birth, signal sig: Int32,
                                    live: (Int32) -> Birth? = { Birth.of($0) }) -> Bool {
        guard pid > 1, live(pid) == expected else { return false }
        // Only ever our own processes: the kernel would let root signal
        // another user's job, and an agent never runs as root.
        guard let identity = ProcTable.identity(of: pid), identity.uid == getuid() else { return false }
        return kill(pid, sig) == 0
    }

    private static func signal(_ pids: [Int32], _ sig: Int32, known: [Int32: Birth]) {
        for pid in pids {
            guard let expected = known[pid] else { continue }
            signalIfSame(pid: pid, expected: expected, signal: sig)
        }
    }

    /// Alive AND still the process we saw: a recycled pid is not "alive" for
    /// this purpose, or the wait would run to the end of the grace period
    /// for a process that is long gone. `birth` nil checks the pid only.
    private static func isAlive(_ pid: Int32, birth: Birth?) -> Bool {
        guard let current = Birth.of(pid) else { return false }
        if let birth { return current == birth }
        return true
    }
}
