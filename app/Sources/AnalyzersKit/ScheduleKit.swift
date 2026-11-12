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
            detail: "+ node_modules of idle repos; package-manager caches (npm's whole cache, pnpm's unreferenced only); ALL unused Docker images (starts Docker if needed, then quits it); deletes Time Machine local snapshots"),
    ]

    /// Human sentence for the INSTALLED schedule — never a hardcoded time.
    /// "Not scheduled" is the honest answer when the agent isn't installed,
    /// which the app previously misreported as its default time.
    public static func describe(_ label: String) -> String {
        switch schedule(for: label) {
        case .daily(let hour, let minute):
            return String(format: "Every day at %d:%02d", hour, minute)
        case .interval(let days):
            return days == 1 ? "Every day" : "Every \(days) days"
        case .alwaysOn:
            return "Always on"
        case nil:
            return "Not scheduled"
        }
    }

    /// True when the agent's plist is actually installed.
    public static func isInstalled(_ label: String) -> Bool {
        FileManager.default.fileExists(atPath: plistURL(for: label).path)
    }

    private static func plistURL(for label: String) -> URL {
        AnalyzersPaths.home.appending(path: "Library/LaunchAgents/\(label).plist")
    }

    /// What the INSTALLED plist passes to the script: `ProgramArguments` after
    /// the script path (the entry before it is the runner). nil when the agent
    /// is not installed.
    public static func programArguments(for label: String) -> [String]? {
        scriptAndArguments(for: label)?.arguments
    }

    /// The script path and arguments the installed plist runs.
    public static func scriptAndArguments(for label: String) -> (script: String, arguments: [String])? {
        guard let data = try? Data(contentsOf: plistURL(for: label)),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let program = dict["ProgramArguments"] as? [String],
              let at = program.firstIndex(where: { $0.hasSuffix(".sh") })
        else { return nil }
        return (program[at], Array(program[(at + 1)...]))
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

    /// What came of saving a schedule and reloading its agent. A failure
    /// carries a sentence that is ready to show.
    public enum ApplyOutcome: Equatable, Sendable {
        case applied
        case failed(String)
    }

    /// Write the schedule into the installed plist and reload the agent.
    /// Blocks for as long as launchd needs (a few seconds at most), so call it
    /// off the main thread.
    public static func apply(_ schedule: Schedule, to label: String) -> ApplyOutcome {
        let name = jobs.first { $0.label == label }?.displayName ?? label
        let url = plistURL(for: label)
        guard let data = try? Data(contentsOf: url),
              var dict = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        else { return .failed("\(name) isn't installed — install the background jobs from Setup first.") }

        switch schedule {
        case .daily(let hour, let minute):
            dict["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
            dict.removeValue(forKey: "StartInterval")
        case .interval(let days):
            dict["StartInterval"] = days * 86_400
            dict.removeValue(forKey: "StartCalendarInterval")
        case .alwaysOn:
            // the guard's mode isn't editable here
            return .failed("\(name) always runs; it has no schedule to change.")
        }

        guard let out = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        ), (try? out.write(to: url)) != nil
        else { return .failed("Couldn't save the new schedule for \(name).") }

        switch reload(label: label, plist: url) {
        case .loaded:
            return .applied
        case .stillOldSettings:
            return .failed("\(name) is still running its previous schedule. The new one is saved and will be used after you log in again; to switch now, apply again in a minute.")
        case .notLoaded(let said):
            return .failed("\(name) could not be loaded again — macOS said: \(said). Apply again; if it keeps failing, log out and back in.")
        }
    }

    public enum ReloadResult: Equatable, Sendable {
        /// Loaded from the plist on disk.
        case loaded
        /// Could not be loaded, and the old definition is still in place.
        case stillOldSettings
        /// Could not be loaded and nothing is loaded; carries launchd's message.
        case notLoaded(String)
    }

    /// Replaces a loaded launchd agent with the plist on disk and says plainly
    /// whether it is loaded afterwards.
    ///
    /// `launchctl bootout` returns before launchd has finished removing a
    /// service whose process is still exiting, and a `bootstrap` sent in that
    /// window fails with "Bootstrap failed: 5: Input/output error" — leaving
    /// the agent on its old definition or not loaded at all. So: ask it to go,
    /// wait (bounded) until `launchctl print` no longer finds it, load the new
    /// one, and try again if launchd is not ready. The same sequence as
    /// `lib/launchd-reload.sh`, which the shell installers use.
    public static func reload(label: String, plist: URL,
                              domain: String = "gui/\(getuid())") -> ReloadResult {
        let service = "\(domain)/\(label)"
        if isLoaded(service) {
            launchctl(["bootout", service])
            // up to 10 s for the old service to disappear
            var waited = 0
            while isLoaded(service) && waited < 50 {
                Thread.sleep(forTimeInterval: 0.2)
                waited += 1
            }
        }
        var said = ""
        for _ in 0..<5 {
            let result = launchctl(["bootstrap", domain, plist.path])
            if result.status == 0 { return .loaded }
            said = result.message
            Thread.sleep(forTimeInterval: 1)
        }
        return isLoaded(service) ? .stillOldSettings : .notLoaded(said.isEmpty ? "no reason given" : said)
    }

    private static func isLoaded(_ service: String) -> Bool {
        launchctl(["print", service]).status == 0
    }

    /// Runs `launchctl`, returning its exit status and the first line it said.
    @discardableResult
    private static func launchctl(_ args: [String]) -> (status: Int32, message: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (-1, "launchctl could not be started") }
        // read before waiting so a chatty failure can never fill the pipe
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        return (p.terminationStatus, first.trimmingCharacters(in: .whitespaces))
    }
}
