import Foundation

/// Reads and edits the INSTALLED launchd plists' schedules
/// (~/Library/LaunchAgents/com.mac-analyzers.*). The repo templates keep the
/// defaults; the manage-agents installers preserve a customized schedule
/// across reinstalls/upgrades, so edits made here stick.
public enum ScheduleKit {

    public enum Schedule: Equatable, Sendable {
        case daily(hour: Int, minute: Int)     // StartCalendarInterval
        case interval(days: Int)               // StartInterval (seconds / 86400)
        case alwaysOn                          // KeepAlive (the guard)
    }

    public struct Job: Identifiable, Sendable {
        public let label: String
        public let displayName: String
        public let detail: String
        public var id: String { label }
    }

    public static let jobs: [Job] = [
        Job(label: "com.mac-analyzers.memory-autoclean.daily",
            displayName: "Memory auto-clean",
            detail: "Daily reaper — orphaned dev/AI servers, stale headless browsers"),
        Job(label: "com.mac-analyzers.storage-autoclean.daily",
            displayName: "Storage daily clean",
            detail: "Stale build caches only"),
        Job(label: "com.mac-analyzers.storage-autoclean.deep",
            displayName: "Storage deep clean",
            detail: "+ node_modules of idle repos, Docker, TM snapshots"),
    ]

    private static func plistURL(for label: String) -> URL {
        AnalyzersPaths.home.appending(path: "Library/LaunchAgents/\(label).plist")
    }

    public static func schedule(for label: String) -> Schedule? {
        guard let data = try? Data(contentsOf: plistURL(for: label)),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return nil }
        if let cal = dict["StartCalendarInterval"] as? [String: Any],
           let hour = cal["Hour"] as? Int, let minute = cal["Minute"] as? Int {
            return .daily(hour: hour, minute: minute)
        }
        if let interval = dict["StartInterval"] as? Int {
            return .interval(days: max(1, interval / 86_400))
        }
        if dict["KeepAlive"] != nil { return .alwaysOn }
        return nil
    }

    /// Write the schedule into the installed plist and reload the agent.
    @discardableResult
    public static func apply(_ schedule: Schedule, to label: String) -> Bool {
        let url = plistURL(for: label)
        guard let data = try? Data(contentsOf: url),
              var dict = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return false }

        switch schedule {
        case .daily(let hour, let minute):
            dict["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
            dict.removeValue(forKey: "StartInterval")
        case .interval(let days):
            dict["StartInterval"] = days * 86_400
            dict.removeValue(forKey: "StartCalendarInterval")
        case .alwaysOn:
            return false   // the guard's mode isn't editable here
        }

        guard let out = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        ) else { return false }
        do { try out.write(to: url) } catch { return false }

        // reload so launchd picks the new schedule up
        let uid = getuid()
        run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        return run("/bin/launchctl", ["bootstrap", "gui/\(uid)", url.path])
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
