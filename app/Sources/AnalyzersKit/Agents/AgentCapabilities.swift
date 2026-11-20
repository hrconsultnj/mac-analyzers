import Foundation

/// What the agent may do. One fixed catalog: the Capabilities screen toggles
/// these by id, `ConfigStore` serializes the enabled set as `AGENT_CAPABILITIES`,
/// and the agent's tool registry refuses anything not in the set. An id in the
/// config that is not in the catalog is dropped on load — a capability the app
/// does not know is a capability the agent does not get.
public struct AgentCapability: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    /// Whether the toggle starts on (a fresh install, or an empty config value).
    public let defaultOn: Bool
    /// True only for the one capability that can change files: its every run
    /// goes through the preview screen and `JobStore.apply(from:approved:)`,
    /// so the applied set is always exactly what the user ticked.
    public let applyGated: Bool

    public init(id: String, title: String, summary: String, defaultOn: Bool, applyGated: Bool = false) {
        self.id = id
        self.title = title
        self.summary = summary
        self.defaultOn = defaultOn
        self.applyGated = applyGated
    }
}

extension AgentCapability {
    /// The fixed catalog, in the order the Capabilities screen lists it.
    /// Read-only work first, the apply-gated one last.
    public static let all: [AgentCapability] = [
        AgentCapability(
            id: "readReports",
            title: "Read my reports",
            summary: "Reads the scans the suite already wrote, and answers questions about them in plain words.",
            defaultOn: true),
        AgentCapability(
            id: "runScans",
            title: "Run scans",
            summary: "Runs the read-only analyzers (storage, memory, network). Scans never change anything.",
            defaultOn: true),
        AgentCapability(
            id: "proposeCleanups",
            title: "Propose cleanups",
            summary: "Suggests what is safe to clean, from the cleaners the app already reviews — always as a list to look at first.",
            defaultOn: true),
        AgentCapability(
            id: "startApprovedCleans",
            title: "Clean what I approved",
            summary: "Runs a cleanup, but only the exact list you ticked on the preview screen, through the same preview and Undo as a manual clean.",
            defaultOn: true,
            applyGated: true),
        AgentCapability(
            id: "suggestRules",
            title: "Suggest better rules",
            summary: "Proposes setting changes from what it sees (a shorter Downloads age, say). Changes go through the same settings and are always yours to make.",
            defaultOn: true),
    ]

    /// The ids enabled by default (a fresh install, or a config with no list).
    public static var defaultEnabledIDs: Set<String> {
        Set(all.filter(\.defaultOn).map(\.id))
    }

    /// The enabled set from a config value: absent or empty means the defaults;
    /// a list means exactly those ids, and only ones the catalog knows. Two
    /// capabilities in the config that the app dropped (an older list naming a
    /// capability that no longer exists) do not silently widen the set.
    public static func enabledIDs(fromConfig raw: String?) -> Set<String> {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return defaultEnabledIDs }
        let known = Set(all.map(\.id))
        let parsed = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return Set(parsed.filter { known.contains($0) })
    }
}

/// What kind of Mac this is, read once and shown where the agent surfaces need
/// it: the On-Device Models screen's banner, Setup's engine offer, and the fit
/// badge on every model card. Reads the system only — no files, no network.
public struct MachineAssessment: Equatable, Sendable {
    /// Total physical memory, in whole GB, rounded to the nearest GB.
    public let physicalMemoryGB: Int
    /// Free space on the data root's volume, in whole GB (important-usage
    /// accounting — the space the system says is actually usable).
    public let freeDiskGB: Int

    /// The survey's memory tiers: 16, 24, 32+ GB, floored — a 48 GB Mac is
    /// tier 32. The catalog orders its recommendations by tier.
    public var tier: Int {
        if physicalMemoryGB >= 32 { return 32 }
        if physicalMemoryGB >= 24 { return 24 }
        return 16
    }

    public static func assess() -> MachineAssessment {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Int((Double(bytes) / 1_073_741_824.0).rounded())
        var freeGB = 0
        if let values = try? FileManager.default.attributesOfFileSystem(
            forPath: AnalyzersPaths.userRoot.path),
            let free = values[.systemFreeSize] as? Int64 {
            freeGB = Int((Double(free) / 1_073_741_824.0).rounded())
        }
        return MachineAssessment(physicalMemoryGB: memoryGB, freeDiskGB: freeGB)
    }

    /// Whether a model estimated to need `modelMemoryGB` resident can run here:
    /// the model plus a headroom for the system and this app against total RAM.
    /// The headroom is deliberate — a Mac that cannot keep the model and its
    /// own work in memory should be told "won't fit", not swapped to death.
    public func canFit(modelMemoryGB: Double) -> Bool {
        Double(physicalMemoryGB) - modelMemoryGB >= 6
    }

    /// The three-word verdict a model card shows: plenty of room, tight but
    /// workable, or not on this Mac.
    public func fit(modelMemoryGB: Double, downloadGB: Double) -> ModelFit {
        if !canFit(modelMemoryGB: modelMemoryGB) { return .wontFit }
        if Double(physicalMemoryGB) - modelMemoryGB < 10 || Double(freeDiskGB) < downloadGB + 5 { return .tight }
        return .fitsWell
    }
}

/// How well one model fits this Mac.
public enum ModelFit: Equatable, Sendable {
    case fitsWell
    case tight
    case wontFit

    public var title: String {
        switch self {
        case .fitsWell: "Fits well"
        case .tight: "Tight"
        case .wontFit: "Won't fit"
        }
    }
}
