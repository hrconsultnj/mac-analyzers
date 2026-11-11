import Foundation

/// A temporary folder for a probe that is removed when the process ends, however it ends. `exit` runs no `defer`, so
/// a probe that cleans up with `defer` leaves its folder behind on every run (hundreds after a few gate runs);
/// this removes each folder from an `atexit` handler instead.
enum ProbeTemp {
    // written before the probe does anything else and read once by the exit handler: no concurrent access
    nonisolated(unsafe) private static var folders: [String] = []
    nonisolated(unsafe) private static var registered = false

    /// Makes `<temporary directory>/<prefix>-<uuid>` and arranges for it to be removed at exit.
    static func make(_ prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url.path)
        if !registered {
            registered = true
            atexit { for path in ProbeTemp.folders { try? FileManager.default.removeItem(atPath: path) } }
        }
        return url
    }
}
