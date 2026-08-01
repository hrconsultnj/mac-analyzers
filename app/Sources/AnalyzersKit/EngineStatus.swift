import Foundation

/// What is ACTUALLY installed and loaded, asked of the system rather than
/// assumed. The app used to infer "the guard is active" from the absence of
/// a pause-flag file — so a Mac with no engine installed showed a green
/// shield. A tool that reports protection it does not have is worse than one
/// that reports nothing.
public struct EngineStatus: Sendable {

    public enum AgentState: Sendable, Equatable {
        case loaded          // launchctl knows it
        case notInstalled    // no plist / launchctl doesn't know it
    }

    public let suiteRootExists: Bool
    public let scriptsPresent: Bool
    public let guardAgent: AgentState
    public let cleanerAgents: [String: AgentState]
    /// The guard process itself — loaded ≠ running (it can have crashed).
    public let guardProcessRunning: Bool
    public let guardPaused: Bool

    public static let guardLabel = "com.mac-analyzers.memory-guard"
    public static let cleanerLabels = [
        "com.mac-analyzers.memory-autoclean.daily",
        "com.mac-analyzers.storage-autoclean.daily",
        "com.mac-analyzers.storage-autoclean.deep",
    ]

    /// Everything installed and the guard loaded — the only state that earns
    /// a green "Active".
    public var isFullyInstalled: Bool {
        suiteRootExists && scriptsPresent && guardAgent == .loaded
    }

    public var anyCleanerLoaded: Bool {
        cleanerAgents.values.contains(.loaded)
    }

    /// One honest sentence for the UI.
    public var summary: String {
        if !suiteRootExists || !scriptsPresent { return "Not installed" }
        if guardAgent != .loaded { return "Not installed" }
        if guardPaused { return "Paused" }
        if !guardProcessRunning { return "Not running" }
        return "Active"
    }

    // MARK: - probe (blocking; call through the load coordinator)

    public static func probe() -> EngineStatus {
        let fm = FileManager.default
        let root = AnalyzersPaths.suiteRoot
        let rootExists = fm.fileExists(atPath: root.path)
        let scripts = [
            "memory-analyzer/memory-guard.sh",
            "memory-analyzer/memory-auto-clean.sh",
            "storage-analyzer/storage-auto-clean.sh",
        ].allSatisfy { fm.isExecutableFile(atPath: root.appending(path: $0).path) }

        var cleaners: [String: AgentState] = [:]
        for label in cleanerLabels {
            cleaners[label] = isLoaded(label) ? .loaded : .notInstalled
        }

        return EngineStatus(
            suiteRootExists: rootExists,
            scriptsPresent: scripts,
            guardAgent: isLoaded(guardLabel) ? .loaded : .notInstalled,
            cleanerAgents: cleaners,
            guardProcessRunning: pgrepGuard(),
            guardPaused: fm.fileExists(atPath: AnalyzersPaths.guardPauseFlag.path))
    }

    /// `launchctl print gui/<uid>/<label>` — exit 0 means launchd knows it.
    private static func isLoaded(_ label: String) -> Bool {
        run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]) == 0
    }

    private static func pgrepGuard() -> Bool {
        run("/usr/bin/pgrep", ["-f", "memory-guard.sh"]) == 0
    }

    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
