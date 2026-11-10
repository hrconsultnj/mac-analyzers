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

    /// Leaf-first SIGTERM of the tree under `root` (and `root` itself, last),
    /// then SIGKILL of anything still alive once `grace` has passed.
    ///
    /// While waiting, the tree is re-walked: a script that was between two
    /// commands when its first child died starts the next one, and that one
    /// gets the same treatment. Every pid ever seen is remembered, because a
    /// child whose parent already died is re-parented to launchd and is no
    /// longer found by walking from `root`.
    public static func terminate(root: Int32, grace: Duration = defaultGrace) async {
        guard root > 1 else { return }
        var known: Set<Int32> = [root]
        let first = descendants(of: root)
        known.formUnion(first)
        signal(first + [root], SIGTERM)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: grace)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            if isAlive(root) {
                let late = descendants(of: root).filter { !known.contains($0) }
                if !late.isEmpty {
                    known.formUnion(late)
                    signal(late, SIGTERM)
                }
            }
            if !known.contains(where: isAlive) { return }
        }
        signal(known.filter(isAlive).sorted(by: >), SIGKILL)
    }

    /// Pids of `root`'s descendants that are still alive — what a cancel
    /// check ("did it leave children behind?") looks at.
    public static func livingDescendants(of root: Int32) -> [Int32] {
        descendants(of: root).filter(isAlive)
    }

    private static func signal(_ pids: [Int32], _ signal: Int32) {
        let me = getuid()
        for pid in pids where pid > 1 {
            // Only ever our own processes: a pid can be recycled in the grace
            // window, and the kernel would let us signal another user's job
            // only if we were root.
            guard let identity = ProcTable.identity(of: pid), identity.uid == me else { continue }
            kill(pid, signal)
        }
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
