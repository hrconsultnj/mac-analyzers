import Foundation

/// Runs an engine cleaner script and captures its output. The engine stays
/// bash and stays the authority: scripts are dry-run by default and only act
/// under --apply, so the app can never make them do more than a user could
/// from the terminal. Runs land in the same logs the log panes read.
public enum ActionRunner {

    public struct RunResult: Sendable {
        public let exitCode: Int32
        public let output: String
    }

    public static func run(script: URL, args: [String]) async -> RunResult {
        // A missing engine used to arrive as exit code -1 with the reason
        // buried in the output string, which every caller then rendered as
        // "the script stopped with code -1". Say it plainly instead.
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            return RunResult(
                exitCode: 127,
                output: "engine missing: \(script.lastPathComponent) was not found at \(script.path)")
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path] + args
            process.currentDirectoryURL = script.deletingLastPathComponent()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: RunResult(
                    exitCode: finished.terminationStatus,
                    output: String(data: data, encoding: .utf8) ?? ""))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: RunResult(
                    exitCode: -1,
                    output: "could not launch \(script.lastPathComponent): \(error.localizedDescription)"))
            }
        }
    }
}

public extension AnalyzersPaths {
    static let memoryCleanScript = suiteRoot.appending(path: "memory-analyzer/memory-auto-clean.sh")
    static let reclaimScript = suiteRoot.appending(path: "memory-analyzer/memory-reclaim.sh")
    static let storageCleanScript = suiteRoot.appending(path: "storage-analyzer/storage-auto-clean.sh")
    static let janitorScript = suiteRoot.appending(path: "storage-analyzer/downloads-janitor.sh")
    static let janitorLog = storageReports.appending(path: "janitor.log")
    /// The two read-only analyzers. They only ever write a markdown report —
    /// the README leads with these, and until now nothing in the app could
    /// run them.
    static let memoryAnalyzeScript = suiteRoot.appending(path: "memory-analyzer/analyze.sh")
    static let storageAnalyzeScript = suiteRoot.appending(path: "storage-analyzer/analyze.sh")
    static let memoryLatestReport = memoryReports.appending(path: "latest.md")
    static let storageLatestReport = storageReports.appending(path: "latest.md")
}
