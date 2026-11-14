import Foundation
import Dispatch
import Synchronization

/// The folder a snapshot makes in the temp directory (a throwaway job index) goes however the tool ends.
///
/// `finish` removed it on the normal path, but a render that is stopped (a time limit's `kill`, Ctrl-C), or that
/// ends through `exit` elsewhere, left it behind, run after run (368 folders). `exit` runs `atexit` handlers, and a
/// stop signal is handled on a queue of its own (the main thread may be busy), which removes the folders and ends the
/// process with the signal's status, so the folder is removed on every path except SIGKILL. The probes in `AgentRunner` do the same with `ProbeScratch`; the two tools do not import each other.
enum SnapshotScratch {

    private static let paths = Mutex<[String]>([])
    private static let signalQueue = DispatchQueue(label: "snapshot-scratch.signals")
    // the sources must stay alive for the life of the process: written once on the main thread by `arm`
    nonisolated(unsafe) private static var listeners: [DispatchSourceSignal] = []

    /// A new folder under the temp directory, `prefix-<uuid>`, removed however the tool ends.
    @MainActor static func folder(_ prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        arm(url)
        return url
    }

    /// A folder made elsewhere, removed however the tool ends. The first call installs the exit and signal handling.
    @MainActor static func arm(_ folder: URL) {
        let first = paths.withLock { current -> Bool in
            defer { current.append(folder.path) }
            return current.isEmpty
        }
        guard first else { return }
        atexit { SnapshotScratch.remove() }
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            listeners.append(stopSource(for: signalNumber))
        }
    }

    /// Not main-actor isolated, so its handler may run on `signalQueue` without the runtime checking for the main queue.
    ///
    /// On a queue of its own, NOT the main one: a busy or stuck main thread (a render in the middle of its work, the
    /// main queue not served) would hold the stop back, and a time limit that sends SIGTERM would not stop it.
    private static func stopSource(for signalNumber: Int32) -> DispatchSourceSignal {
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
        source.setEventHandler {
            // Removing the folders while the main thread may be writing into them is harmless: a write into a folder that
            // is gone fails, the writer is `try?` or about to die, and nothing here waits for it. `_exit` ends the process
            // at once with the status a signal gives (143 for SIGTERM, 130 for SIGINT, 129 for SIGHUP) and, unlike
            // `exit`, runs no handlers that need the main thread. Programs the render started are not stopped by this.
            SnapshotScratch.remove()
            _exit(128 + signalNumber)
        }
        source.resume()
        return source
    }

    static func remove() {
        let folders = paths.withLock { current -> [String] in defer { current = [] }; return current }
        for folder in folders { try? FileManager.default.removeItem(atPath: folder) }
    }
}
