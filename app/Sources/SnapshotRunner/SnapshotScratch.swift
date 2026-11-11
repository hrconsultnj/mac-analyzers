import Foundation
import Dispatch
import Synchronization

/// The folder a snapshot makes in the temp directory (a throwaway job index) goes however the tool ends.
///
/// `finish` removed it on the normal path, but a render that is stopped (a time limit's `kill`, Ctrl-C), or that
/// ends through `exit` elsewhere, left it behind, run after run (368 folders). `exit` runs `atexit` handlers, and a
/// stop signal is turned into an ordinary exit on the main queue, so the folder is removed on every path except
/// SIGKILL. The probes in `AgentRunner` do the same with `ProbeScratch`; the two tools do not import each other.
enum SnapshotScratch {

    private static let paths = Mutex<[String]>([])
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
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { exit(128 + signalNumber) }
            source.resume()
            listeners.append(source)
        }
    }

    static func remove() {
        let folders = paths.withLock { current -> [String] in defer { current = [] }; return current }
        for folder in folders { try? FileManager.default.removeItem(atPath: folder) }
    }
}
