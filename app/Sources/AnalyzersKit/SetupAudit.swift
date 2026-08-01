import Foundation
import ServiceManagement
import UserNotifications

/// What this Mac can actually do right now — every row DETECTED, never
/// assumed. A first-run checklist that ticks boxes because the app just
/// asked for something is worse than no checklist: it certifies a machine
/// that cannot run the product.
///
/// Each row also carries its own repair, so a red row is a button rather
/// than an instruction to go find System Settings.
public struct SetupCheck: Identifiable, Sendable {

    public enum Verdict: Sendable, Equatable {
        /// Working. `detail` says what was found.
        case ready
        /// Not working, and it stops the product doing its job.
        case blocking
        /// Not working, but only some of the product is affected.
        case degraded
        /// Nothing to fix — a choice the user has not made yet.
        case unset

        public var isDone: Bool { self == .ready }
    }

    public enum Repair: Sendable, Equatable {
        case installAgents
        case requestNotifications
        case openNotificationSettings
        case enableLoginItem
        case openLoginItemSettings
        case writeConfig
        case setMemoryCap(Int)
        case openPane(String)
        case sendTestNotification
        case openFullDiskAccess
        case openAutomationSettings
        case none
    }

    public let id: String
    public let title: String
    /// One sentence, plain English, no jargon — what this gets the user.
    public let why: String
    public let verdict: Verdict
    /// The evidence: what was actually found on this Mac.
    public let detail: String
    public let repair: Repair
    public let repairTitle: String?

    public init(id: String, title: String, why: String, verdict: Verdict,
                detail: String, repair: Repair = .none, repairTitle: String? = nil) {
        self.id = id
        self.title = title
        self.why = why
        self.verdict = verdict
        self.detail = detail
        self.repair = repair
        self.repairTitle = repairTitle
    }
}

public struct SetupReport: Sendable {
    public let checks: [SetupCheck]

    public var ready: Int { checks.filter { $0.verdict == .ready }.count }
    public var total: Int { checks.count }
    public var blocking: [SetupCheck] { checks.filter { $0.verdict == .blocking } }
    public var degraded: [SetupCheck] { checks.filter { $0.verdict == .degraded } }
    /// Nothing red — the product can do the job it advertises.
    public var isUsable: Bool { blocking.isEmpty }
    public var isComplete: Bool { ready == total }
}

public enum SetupAudit {

    /// Blocking work — run it off the main actor (through the load layer).
    /// `notifications` and `loginItem` are read live by the caller because
    /// both are async system queries; everything else is answered here.
    public static func probe(notifications: SetupCheck,
                             loginItem: SetupCheck) -> SetupReport {
        let engine = EngineStatus.probe()
        var checks: [SetupCheck] = []

        // 1 — the engine itself
        checks.append(engineCheck(engine))

        // 2 — the background jobs
        checks.append(agentsCheck(engine))

        // 3/4 — asked of the system by the caller (async APIs)
        checks.append(notifications)
        checks.append(loginItem)

        // 5 — settings file
        checks.append(configCheck())

        // 6 — memory cap sanity against this Mac's actual RAM
        checks.append(memoryCapCheck())

        // 7 — protected apps
        checks.append(protectedAppsCheck())

        // 8 — permissions the cleaners need
        checks.append(fullDiskAccessCheck())
        checks.append(automationCheck())

        return SetupReport(checks: checks)
    }

    // MARK: - individual probes

    static func engineCheck(_ engine: EngineStatus) -> SetupCheck {
        guard engine.suiteRootExists && engine.scriptsPresent else {
            return SetupCheck(
                id: "engine", title: "Analyzer scripts",
                why: "The part that does the actual watching and cleaning.",
                verdict: .blocking,
                detail: "Not found. Reinstall Mac Analyzers to restore them.",
                repair: .none)
        }
        return SetupCheck(
            id: "engine", title: "Analyzer scripts",
            why: "The part that does the actual watching and cleaning.",
            verdict: .ready,
            detail: AnalyzersPaths.usingBundledEngine
                ? "Included with the app — nothing else to install."
                : "Running from your copy at ~/mac-analyzers.")
    }

    static func agentsCheck(_ engine: EngineStatus) -> SetupCheck {
        let loadedCleaners = engine.cleanerAgents.values.filter { $0 == .loaded }.count
        let loaded = loadedCleaners + (engine.guardAgent == .loaded ? 1 : 0)
        let total = EngineStatus.cleanerLabels.count + 1
        if loaded == total {
            return SetupCheck(
                id: "agents", title: "Automatic protection",
                why: "Watches memory continuously and tidies up on a schedule, without you opening anything.",
                verdict: .ready, detail: "All \(total) background jobs are installed and loaded.")
        }
        return SetupCheck(
            id: "agents", title: "Automatic protection",
            why: "Watches memory continuously and tidies up on a schedule, without you opening anything.",
            verdict: loaded == 0 ? .blocking : .degraded,
            detail: loaded == 0
                ? "None of the \(total) background jobs are installed, so nothing runs unless you press a button."
                : "\(loaded) of \(total) background jobs are loaded.",
            repair: .installAgents,
            repairTitle: loaded == 0 ? "Turn on automatic protection" : "Install the rest")
    }

    static func configCheck() -> SetupCheck {
        let exists = FileManager.default.fileExists(atPath: AnalyzersPaths.configLocal.path)
        return SetupCheck(
            id: "config", title: "Your settings file",
            why: "Holds your memory limit, your protected apps and your schedule — it is never overwritten by an update.",
            verdict: exists ? .ready : .unset,
            detail: exists
                ? "Saved at ~/mac-analyzers/config.local.sh."
                : "Not created yet. It is written the first time you save a setting.",
            repair: exists ? .none : .writeConfig,
            repairTitle: exists ? nil : "Create it with the defaults")
    }

    /// The shipped 6144 MB default is 37.5 % of a 16 GB Mac — high enough that
    /// the guard would rarely act. A cap should track the machine.
    static func memoryCapCheck() -> SetupCheck {
        let installedMB = Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024)
        let suggested = max(1024, (installedMB / 5) / 256 * 256)
        let current = ConfigReader.intValue(forKey: "GUARD_HARD_CAP_MB") ?? 6144
        let installedGB = installedMB / 1024
        let deviation = abs(Double(current - suggested)) / Double(max(suggested, 1))
        if deviation <= 0.25 {
            return SetupCheck(
                id: "cap", title: "Memory limit",
                why: "How much memory one app may hold before the guard steps in.",
                verdict: .ready,
                detail: "\(current) MB, which suits a \(installedGB) GB Mac.")
        }
        return SetupCheck(
            id: "cap", title: "Memory limit",
            why: "How much memory one app may hold before the guard steps in.",
            verdict: .degraded,
            detail: current > suggested
                ? "\(current) MB is high for a \(installedGB) GB Mac — a runaway app could take a fifth of your memory before anything happens."
                : "\(current) MB is low for a \(installedGB) GB Mac — normal apps may be stopped.",
            repair: .setMemoryCap(suggested),
            repairTitle: "Use \(suggested) MB")
    }

    static func protectedAppsCheck() -> SetupCheck {
        let list = ConfigReader.listValue(forKey: "ANALYZERS_PROTECT_EXTRA")
        return SetupCheck(
            id: "protected", title: "Apps that are never touched",
            why: "Anything on this list is left alone, whatever it is doing.",
            verdict: list.isEmpty ? .unset : .ready,
            detail: list.isEmpty
                ? "Nothing added yet. The built-in safety rules still apply."
                : "\(list.count) app\(list.count == 1 ? "" : "s") protected: \(list.prefix(3).joined(separator: ", "))\(list.count > 3 ? "…" : "").",
            repair: .openPane("memory"),
            repairTitle: list.isEmpty ? "Choose apps" : "Review the list")
    }

    /// Reading a file inside a TCC-protected folder is the only honest test —
    /// the permission cannot be queried, only exercised.
    static func fullDiskAccessCheck() -> SetupCheck {
        let probe = AnalyzersPaths.home.appending(path: "Library/Application Support/com.apple.TCC")
        let readable = (try? FileManager.default.contentsOfDirectory(
            atPath: probe.path)) != nil
        return SetupCheck(
            id: "fda", title: "Permission to see every folder",
            why: "Without it, the storage report silently skips whole folders and under-reports what is using your disk.",
            verdict: readable ? .ready : .degraded,
            detail: readable
                ? "Granted — the storage report can see everything."
                : "Not granted. Reports still work, but some folders will be missing.",
            repair: readable ? .none : .openFullDiskAccess,
            repairTitle: readable ? nil : "Open the setting")
    }

    static func automationCheck() -> SetupCheck {
        let granted = UserDefaults.standard.bool(forKey: "automationProven")
        return SetupCheck(
            id: "automation", title: "Permission to quit apps politely",
            why: "Lets the reclaim ask an app to quit the same way you would, so unsaved work is never lost.",
            verdict: granted ? .ready : .unset,
            detail: granted
                ? "Granted — apps can be asked to quit rather than force-stopped."
                : "macOS asks the first time it is needed. Until then this is unknown.",
            repair: .openAutomationSettings,
            repairTitle: "Open the setting")
    }
}

/// Minimal reader for the shell config the app and the engine share. The
/// app writes it; this reads the values back so the checklist reports what
/// is really in the file rather than what the UI last had in memory.
enum ConfigReader {
    static func rawValue(forKey key: String) -> String? {
        guard let text = try? String(contentsOf: AnalyzersPaths.configLocal,
                                     encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key)=") || trimmed.hasPrefix("export \(key)=") else { continue }
            let value = trimmed.split(separator: "=", maxSplits: 1)[1]
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return nil
    }

    static func intValue(forKey key: String) -> Int? {
        rawValue(forKey: key).flatMap { Int($0) }
    }

    static func listValue(forKey key: String) -> [String] {
        guard let raw = rawValue(forKey: key) else { return [] }
        return raw.split(whereSeparator: { $0 == "|" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
