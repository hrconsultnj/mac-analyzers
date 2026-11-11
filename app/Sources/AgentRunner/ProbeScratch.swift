import AnalyzersKit
import Foundation
import Synchronization

/// Every folder a probe makes, and every program it starts, is registered here and removed when the probe ENDS.
///
/// A probe finishes with `exit(...)`, and `exit` runs no `defer`: the temporary folder a probe removed in a `defer`
/// was never removed, and each run of the push gate left several (the temp directory held 481 of them, 5.8 GB, the
/// largest written by the run matcher's 32 MB log). `exit` DOES run `atexit` handlers, so a folder registered here
/// goes whichever way the probe ends, including a path nobody converted to `finish`.
///
///     let dir = ProbeScratch.folder("ma-probe-thing")      // made, and removed at the end
///     ProbeScratch.track(process)                          // ended at the end if still running
///     ProbeScratch.finish(failed ? 1 : 0)                  // removes, stops, exits
///
/// `scripts/check.sh probes` gives each probe a private `MA_PROBE_TMP`, fails, naming the probe, if anything is left in
/// it, and refuses a probe source that asks for the temp directory itself instead of using this.
enum ProbeScratch {

    private struct State {
        var folders: [String] = []
        var pids: [Int32] = []
        var armed = false
    }
    private static let state = Mutex(State())

    /// Where probe scratch goes: the folder `scripts/check.sh probes` names in `MA_PROBE_TMP` (a private one per probe,
    /// so what is left in it after the probe is that probe's and nobody else's, even while another session runs
    /// its own probes), else the temp directory. This tool is not shipping code, so it may read the environment.
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["MA_PROBE_TMP"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }

    /// A new folder under `root`, `prefix-<uuid>`, removed when the probe ends.
    static func folder(_ prefix: String) -> URL {
        let url = root.appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        register(url)
        return url
    }

    /// A file or folder the probe made itself, to be removed when it ends.
    static func register(_ url: URL) {
        arm()
        state.withLock { $0.folders.append(url.path) }
    }

    /// A program the probe started, ended when the probe ends if it is still running.
    static func track(_ process: Process) {
        arm()
        let pid = process.processIdentifier
        state.withLock { $0.pids.append(pid) }
    }

    /// Removes what was registered, stops what was tracked, and exits with `status`.
    static func finish(_ status: Int32) -> Never {
        cleanup()
        exit(status)
    }

    static func cleanup() {
        let (folders, pids) = state.withLock { current -> ([String], [Int32]) in
            defer { current.folders = []; current.pids = [] }
            return (current.folders, current.pids)
        }
        // Only a program that is still this probe's own child is signalled. One that already ended and was collected
        // has given its number back, and the system may have handed that number to someone else's program.
        let me = Int(getpid())
        for pid in pids where pid > 1 && ProcTable.identity(of: pid)?.ppid == me { kill(pid, SIGTERM) }
        for path in folders { try? FileManager.default.removeItem(atPath: path) }
    }

    private static func arm() {
        let first = state.withLock { current -> Bool in
            defer { current.armed = true }
            return !current.armed
        }
        if first { atexit { ProbeScratch.cleanup() } }
    }
}
