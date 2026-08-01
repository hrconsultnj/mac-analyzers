import Foundation
import os

/// Watches the places software installs itself to run at login/boot
/// (LaunchAgents/LaunchDaemons). Additions are worth telling the user
/// about — "X just installed a login item" is exactly the kind of silent
/// change this suite exists to surface. Report-only, never acts.
public enum PersistenceWatcher {

    public static let stateFile = AnalyzersPaths.suiteRoot
        .appending(path: "reports/persistence-state.json")
    public static let logFile = AnalyzersPaths.suiteRoot
        .appending(path: "reports/persistence.log")

    private static var watchedDirs: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents"),
         URL(fileURLWithPath: "/Library/LaunchAgents"),
         URL(fileURLWithPath: "/Library/LaunchDaemons")]
    }

    /// Compare against the stored snapshot. Returns NEW paths (additions
    /// only — removals and edits stay out of v1 to avoid alarm noise).
    /// First run seeds the snapshot silently and returns nothing.
    public static func checkForAdditions() -> [String] {
        let current = snapshot()
        let fm = FileManager.default

        guard fm.fileExists(atPath: stateFile.path),
              let data = try? Data(contentsOf: stateFile),
              let previous = try? JSONDecoder().decode([String: Double].self, from: data)
        else {
            persist(current)
            appendLog("\(stamp()) BASELINE seeded — \(current.count) persistence item(s) recorded")
            return []
        }

        let additions = current.keys.filter { previous[$0] == nil }.sorted()
        if !additions.isEmpty {
            for path in additions {
                appendLog("\(stamp()) NEW persistence item: \(path)")
            }
        }
        persist(current)
        return additions
    }

    private static func snapshot() -> [String: Double] {
        var result: [String: Double] = [:]
        let fm = FileManager.default
        for dir in watchedDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for file in files where file.pathExtension == "plist" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate)?.timeIntervalSince1970 ?? 0
                result[file.path] = mtime
            }
        }
        return result
    }

    private static func persist(_ state: [String: Double]) {
        try? FileManager.default.createDirectory(
            at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFile, options: .atomic)
        }
    }

    private static func appendLog(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logFile)
        }
        Logger(subsystem: "com.mac-analyzers.app", category: "persistence")
            .notice("\(line, privacy: .public)")
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

public extension AnalyzersPaths {
    static let persistenceLog = suiteRoot.appending(path: "reports/persistence.log")
}
