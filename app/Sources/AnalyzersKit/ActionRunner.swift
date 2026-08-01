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
        await withCheckedContinuation { continuation in
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
}
