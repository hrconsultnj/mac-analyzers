import Foundation

/// Runs an engine script and captures its output, for the call sites that have
/// not moved to tracked jobs yet. A thin wrapper over `EngineProcess`, which
/// reads output while the script runs (no stall on large output), uses the
/// same `PATH` the scheduled runs get, and stops cleanly. The engine stays bash
/// and stays the authority: scripts are dry-run by default and only act under
/// --apply, so the app can never make them do more than a user could from the
/// terminal. Runs land in the same logs the log panes read.
public enum ActionRunner {

    public struct RunResult: Sendable {
        public let exitCode: Int32
        public let output: String
    }

    public static func run(script: URL, args: [String]) async -> RunResult {
        let result = await EngineProcess(script: script, args: args, collectOutput: true).run()
        return RunResult(exitCode: result.exitCode, output: result.output)
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
    /// Spotlight indexing audit + dev-dir fencing. Same dry-run-by-default
    /// contract as the cleaners; the app also flips individual
    /// `.metadata_never_index` markers directly (FileManager), which is
    /// exactly the manual reversal the script itself documents.
    static let spotlightAuditScript = suiteRoot.appending(path: "storage-analyzer/spotlight-audit.sh")
    /// Temp + AI-agent leftovers: audit, reviewed Trash/permanent cleanup,
    /// and ejecting disk images mounted inside temp folders. Dry run unless
    /// --apply; --only-paths narrows an apply to the rows the user kept ticked.
    static let tempCleanScript = suiteRoot.appending(path: "storage-analyzer/temp-clean.sh")
}
