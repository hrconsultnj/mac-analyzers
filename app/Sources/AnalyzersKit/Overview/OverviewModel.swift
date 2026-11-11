import Foundation

/// What Overview says, as typed rows built from plain inputs: the three tiles,
/// what needs attention, what is running, the latest guard events and this
/// week's totals. Pure, so `agent-runner --probe-overview` prints exactly what
/// the screen will show and the screen only draws it.
public struct OverviewModel: Sendable {

    public enum Tone: Sendable { case good, caution, bad, neutral }

    /// A tile: a number and its caption, opening the screen that explains it.
    public struct Tile: Identifiable, Sendable {
        public let id: String
        public let symbol: String
        public let value: String
        public let caption: String
        public let tone: Tone
        /// Deep-link target (`DeepLinkRouter`) the tile opens.
        public let target: String
    }

    /// One thing that needs a person, opening the screen where they act.
    public struct Attention: Identifiable, Sendable {
        public enum Action: Sendable { case open(target: String), resumeGuard }
        public let id: String
        public let symbol: String
        public let title: String
        public let detail: String
        public let tone: Tone
        public let action: Action
    }

    /// A guard event as a named row: what happened to which app, when.
    public struct EventRow: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let outcome: String
        public let when: Date
        /// The parsed event, for the screen's symbol and colour (`GuardEvent.symbol`/`tint`).
        public let event: GuardEvent
        public let tone: Tone
    }

    public struct Week: Sendable, Equatable {
        public var stopped = 0
        public var alerts = 0
        public var freedBytes: Int64 = 0
        public var memoryFreedMB = 0
        public var runs = 0

        public init() {}
        public init(stopped: Int, alerts: Int, freedBytes: Int64, memoryFreedMB: Int, runs: Int) {
            self.stopped = stopped; self.alerts = alerts; self.freedBytes = freedBytes
            self.memoryFreedMB = memoryFreedMB; self.runs = runs
        }

        /// "3 apps stopped · 4.6 GB removed by cleanups", or why there is nothing to say.
        public var summary: String {
            var parts: [String] = []
            if stopped > 0 { parts.append("\(ActivitySummary.plural(stopped, "app", "apps")) stopped") }
            if freedBytes > 0 { parts.append("\(ByteSize.format(freedBytes)) removed by cleanups") }
            if memoryFreedMB > 0 { parts.append("\(MemorySize.text(Int64(memoryFreedMB) * 1_048_576)) of memory recovered") }
            return parts.isEmpty ? "A quiet week — nothing needed defending." : parts.joined(separator: " · ")
        }
    }

    public struct Inputs: Sendable {
        public var pressure: LiveStats.Pressure
        public var engine: EngineStatus?
        public var killsToday: Int
        public var disk: DiskUsage?
        public var runwayText: String?
        public var runwayUrgent: Bool
        public var reclaimableBytes: Int64
        public var thermalElevated: Bool
        public var update: (available: Bool, latest: String?, installed: String)
        public var events: [GuardEvent]
        /// The store's own pause state, which changes the moment Resume is clicked; the engine
        /// snapshot only changes on the next reload.
        public var guardPaused: Bool?

        public init(pressure: LiveStats.Pressure, engine: EngineStatus?, killsToday: Int, disk: DiskUsage?,
                    runwayText: String?, runwayUrgent: Bool, reclaimableBytes: Int64,
                    thermalElevated: Bool, update: (available: Bool, latest: String?, installed: String),
                    events: [GuardEvent], guardPaused: Bool? = nil) {
            self.pressure = pressure; self.engine = engine; self.killsToday = killsToday; self.disk = disk
            self.runwayText = runwayText; self.runwayUrgent = runwayUrgent
            self.reclaimableBytes = reclaimableBytes; self.thermalElevated = thermalElevated
            self.update = update; self.events = events; self.guardPaused = guardPaused
        }
    }

    public let tiles: [Tile]
    public let attention: [Attention]
    public let events: [EventRow]

    public init(_ input: Inputs, resolveName: (GuardEvent) -> String = { $0.displayName }) {
        // the three honest guard states, from what launchd reports
        let guardTile: Tile
        if let engine = input.engine {
            if !engine.isFullyInstalled {
                guardTile = Tile(id: "guard", symbol: "shield.slash", value: "Not Set Up",
                                 caption: "\(Names.Screen.memoryGuard) is not installed yet", tone: .caution,
                                 target: "log:guardLog")
            } else if input.guardPaused ?? engine.guardPaused {
                guardTile = Tile(id: "guard", symbol: "pause.circle.fill", value: "Paused",
                                 caption: "\(Names.Screen.memoryGuard) is taking no action", tone: .caution,
                                 target: "log:guardLog")
            } else if !engine.guardProcessRunning {
                guardTile = Tile(id: "guard", symbol: "exclamationmark.triangle.fill", value: "Not Running",
                                 caption: "\(Names.Screen.memoryGuard) is loaded but not running", tone: .caution,
                                 target: "log:guardLog")
            } else {
                guardTile = Tile(id: "guard", symbol: "shield.lefthalf.filled", value: "Active",
                                 caption: "\(ActivitySummary.plural(input.killsToday, "app", "apps")) stopped today",
                                 tone: .good, target: "log:guardLog")
            }
        } else {
            guardTile = Tile(id: "guard", symbol: "shield.lefthalf.filled", value: "Checking…",
                             caption: Names.Screen.memoryGuard, tone: .neutral, target: "log:guardLog")
        }

        let diskTone: Tone = (input.disk?.usedFraction ?? 0) > 0.9 ? .bad : (input.disk?.usedFraction ?? 0) > 0.75 ? .caution : .neutral
        tiles = [
            Tile(id: "memory", symbol: "memorychip", value: input.pressure.label.components(separatedBy: " —")[0],
                 caption: "Memory Pressure",
                 tone: input.pressure == .normal ? .good : input.pressure == .warning ? .caution : .bad,
                 target: "monitor"),
            guardTile,
            Tile(id: "disk", symbol: diskTone == .neutral ? "internaldrive.fill" : "exclamationmark.triangle.fill",
                 value: input.disk.map { "\($0.freeText) free" } ?? "—",
                 caption: input.runwayText.map { "Full in \($0) at the current pace" }
                     ?? input.disk.map { "\($0.usedText) of \($0.totalText) used" } ?? Names.Screen.disk,
                 tone: diskTone, target: "disk"),
        ]

        var items: [Attention] = []
        if input.thermalElevated {
            items.append(Attention(id: "thermal", symbol: "thermometer.high", title: "Your Mac is throttling to cool down",
                                   detail: "macOS is slowing the CPU. See what is working it hardest.", tone: .bad,
                                   action: .open(target: "monitor")))
        }
        if input.pressure != .normal {
            items.append(Attention(id: "pressure", symbol: "exclamationmark.triangle.fill",
                                   title: "Memory pressure is \(input.pressure.label.components(separatedBy: " —")[0].lowercased())",
                                   detail: "See what is using memory right now.", tone: .caution,
                                   action: .open(target: "monitor")))
        }
        if input.guardPaused ?? input.engine?.guardPaused ?? false {
            items.append(Attention(id: "paused", symbol: "pause.circle.fill", title: "\(Names.Screen.memoryGuard) is paused",
                                   detail: "Nothing is watching for runaway processes.", tone: .caution, action: .resumeGuard))
        }
        if input.update.available, let latest = input.update.latest {
            items.append(Attention(id: "update", symbol: "arrow.down.circle.fill",
                                   title: "\(Names.State.updateAvailable): v\(latest)",
                                   detail: "You have v\(input.update.installed).", tone: .good,
                                   action: .open(target: "update")))
        }
        if input.reclaimableBytes > 1 << 30 {
            items.append(Attention(id: "reclaimable", symbol: "sparkles",
                                   title: "\(ByteSize.format(input.reclaimableBytes)) can be reclaimed",
                                   detail: "From the latest check. Nothing is deleted until you review it.", tone: .neutral,
                                   action: .open(target: "caches")))
        }
        if input.runwayUrgent, let runway = input.runwayText {
            items.append(Attention(id: "runway", symbol: "chart.line.downtrend.xyaxis",
                                   title: "Disk full in \(runway) at the current pace",
                                   detail: "Based on your own cleanup history.", tone: .bad, action: .open(target: "disk")))
        }
        attention = items

        events = Self.eventRows(input.events, limit: 6, resolveName: resolveName)
    }

    /// Guard events as named rows, newest first, as Overview and the menu-bar
    /// panel both list them.
    public static func eventRows(_ events: [GuardEvent], limit: Int,
                                 resolveName: (GuardEvent) -> String = { $0.displayName }) -> [EventRow] {
        events.prefix(limit).map { event in
            EventRow(id: event.id, title: title(of: event, resolveName), outcome: outcome(of: event),
                     when: event.date, event: event, tone: event.isKill ? .bad : .caution)
        }
    }

    /// When the person last pressed Clear on the guard's events (the menu-bar
    /// panel's button), if they did. It hides everything before that moment from
    /// the panel and from Overview; the log keeps it, and Trends still counts it.
    /// Same marker file `GuardLogStore` reads (its accessor is private).
    public static func eventsClearedAt() -> Date? {
        let marker = AnalyzersPaths.memoryReports.appending(path: ".menu-stats-cleared")
        guard let raw = try? String(contentsOf: marker, encoding: .utf8),
              let epoch = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    /// A name a person recognises: the app for an app's event, the thing itself
    /// for a system one ("system memory" is how the log files it, not a name).
    static func title(of event: GuardEvent, _ resolve: (GuardEvent) -> String) -> String {
        switch event.kind {
        case .pressureWarning, .pressureCritical: "Memory Pressure"
        case .forensics: Names.crisisReport
        case .warning: Names.Screen.memoryGuard
        default: resolve(event)
        }
    }

    /// One sentence: what happened and how big it was, no path and no token.
    static func outcome(of event: GuardEvent) -> String {
        switch event.kind {
        case .killed(let reason):
            "Stopped by \(Names.Screen.memoryGuard)" + (event.residentText.map { " — was using \($0)" } ?? "") + " (\(reason))"
        case .stopFailed:
            "It had already ended by the time \(Names.Screen.memoryGuard) acted, so nothing was stopped"
        case .spike:
            "Memory was climbing" + (event.residentText.map { " — at \($0)" } ?? "")
        case .capExceeded: "Went over the memory limit" + (event.residentText.map { " — at \($0)" } ?? "")
        case .cpuHog(let pct, let ticks): "Used \(pct)% of the processor for \(ticks) checks"
        case .pressureWarning: "Warning — memory is being compressed and swapped"
        case .pressureCritical: "Critical — the Mac is short of memory"
        case .warning: event.title
        case .forensics: "A \(Names.crisisReport.lowercased()) was saved"
        }
    }
}
