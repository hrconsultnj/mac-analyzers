import Foundation

/// The launchd labels this suite installs. Every other list reads these raw
/// values. `legacyLabel` is the name a Sparehold install already has, so a
/// schedule can be copied across and the old agent removed.
public enum LaunchdAgentID: String, CaseIterable, Sendable {
    case memoryGuard = "com.sparehold.memory-guard"
    case memoryAutoCleanDaily = "com.sparehold.memory-autoclean.daily"
    case storageAutoCleanDaily = "com.sparehold.storage-autoclean.daily"
    case storageAutoCleanDeep = "com.sparehold.storage-autoclean.deep"

    /// The label this agent used before the rename. Same suffix, old prefix.
    public var legacyLabel: String {
        switch self {
        case .memoryGuard: "com.mac-analyzers.memory-guard"
        case .memoryAutoCleanDaily: "com.mac-analyzers.memory-autoclean.daily"
        case .storageAutoCleanDaily: "com.mac-analyzers.storage-autoclean.daily"
        case .storageAutoCleanDeep: "com.mac-analyzers.storage-autoclean.deep"
        }
    }

    /// The agent for a current or previous label, or nil when it is neither.
    /// A `com.mac-analyzers.*` plist is still installed. The app then runs the
    /// manage-agents install, which copies the schedule and removes the old agent.
    public static func legacyAgentsPresent(home: URL = AnalyzersPaths.home) -> Bool {
        let agents = home.appending(path: "Library/LaunchAgents")
        let fm = FileManager.default
        return allCases.contains { id in
            fm.fileExists(atPath: agents.appending(path: "\(id.legacyLabel).plist").path)
        }
    }

    public static func matching(_ label: String) -> LaunchdAgentID? {
        if let id = LaunchdAgentID(rawValue: label) { return id }
        return allCases.first { $0.legacyLabel == label }
    }
}
