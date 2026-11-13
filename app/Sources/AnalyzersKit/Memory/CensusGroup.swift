import Foundation

/// Every process that belongs to one app, tool or system service, with the
/// memory they hold together — the row that answers "what is this costing
/// me", which a per-process list scatters across dozens of helpers.
public struct CensusGroup: Identifiable, Sendable {

    public enum Category: String, Sendable, CaseIterable, Hashable {
        case apps, tools, system

        public var title: String {
            switch self {
            case .apps: Names.Category.apps
            case .tools: Names.Category.tools
            case .system: Names.Category.system
            }
        }
    }

    /// What quitting the GROUP means — the action a person actually wants
    /// ("close Opera"), as opposed to ending one of its 30 processes.
    public enum QuitScope: Sendable, Equatable {
        /// An app: ask its main process to quit (⌘Q semantics); the helpers
        /// leave with it. Each process is named by pid AND start time, so a
        /// pid that was recycled since the census is never signalled.
        case app([ProcessIdentity])
        /// Command-line tools: ask each top-level program to stop; what it
        /// started stops with it. Which programs, and whether each may be
        /// stopped, is `CensusGroup.programs`.
        case tools([ProcessIdentity])
        /// Part of macOS, or owned by another account — never offered.
        case unavailable
    }

    public let id: String
    public let name: String
    public let category: Category
    /// One plain line on what a macOS service is for, when it is known.
    public let role: String?
    /// The process that stands for the group: icon, dossier, pid.
    public let lead: LiveProcess
    /// Every process in the group, lead included, largest first.
    public let members: [LiveProcess]
    /// The same processes summarized by what they DO ("Tabs and pages",
    /// "Extensions") — how a 30-process app reads as five lines.
    public let parts: [CensusPart]
    public let quit: QuitScope
    /// A tools group's separate programs (empty for an app or macOS): the top
    /// process of each and everything it started. A stop is chosen from
    /// these, never from the group's name.
    public let programs: [StopTarget]
    /// Live coding sessions that run inside this app (apps only): agent → how
    /// many. Quitting the app ends them, so the dialog says so.
    public let hostedSessions: [String: Int]
    /// What the group IS inside its category (a browser, a dev server, a macOS service). One reading, from the
    /// catalog in `memory-analyzer/rules/kinds.json`: the Monitor, the menu-bar panel and the guard all read this.
    public let kind: ProcessKind
    /// Which rule decided the kind, and whether it rests on an identity or only on a name.
    public let kindMatch: KindMatch
    /// Why this group is left alone or handled with care, in words: part of macOS, another account's, a live coding
    /// session, a Connection Tool. Says only what Monitor's Stop and Quit do. nil when nothing is held back.
    public let leftAlone: String?

    public var totalBytes: Int64 { members.reduce(0) { $0 + $1.memoryBytes } }
    public var totalText: String { MemorySize.text(totalBytes) }

    /// "8 tabs and pages, 3 extensions, 2 for graphics, 11 other helpers" —
    /// the group at a glance, the parts a person recognizes first. nil when
    /// every process does the same job (nothing to summarize).
    public var partsSummary: String? {
        let helpers = parts.filter { $0.kind != .main }
        guard parts.count > 1, !helpers.isEmpty else { return nil }
        return helpers
            .sorted { $0.kind.summaryOrder != $1.kind.summaryOrder
                ? $0.kind.summaryOrder < $1.kind.summaryOrder
                : $0.members.count > $1.members.count }
            .prefix(4)
            .map { "\($0.members.count) \($0.members.count == 1 ? $0.one : $0.many)" }
            .joined(separator: ", ")
    }

    /// Same group, narrowed to some of its processes (a search hit on a
    /// helper keeps the family row but only the helpers that matched).
    public func keeping(_ kept: [LiveProcess]) -> CensusGroup {
        let keptPIDs = Set(kept.map(\.pid))
        return CensusGroup(
            id: id, name: name, category: category, role: role, lead: lead,
            members: kept,
            parts: parts.compactMap { $0.keeping(keptPIDs) },
            quit: quit,
            programs: programs.compactMap { $0.keeping(keptPIDs) },
            hostedSessions: hostedSessions, kind: kind, kindMatch: kindMatch, leftAlone: leftAlone)
    }
}

/// The processes of one group that do the same job.
public struct CensusPart: Identifiable, Sendable {

    public enum Kind: String, Sendable, Hashable {
        case main, pages, extensions, graphics, network, helper
        /// A named program inside a tool group ("AI tool server (MCP)").
        case named

        /// What a person recognizes first comes first in the summary.
        var summaryOrder: Int {
            switch self {
            case .main: 0
            case .pages: 1
            case .extensions: 2
            case .named: 3
            case .graphics: 4
            case .network: 5
            case .helper: 6
            }
        }
    }

    public let kind: Kind
    /// Row title: "Tabs and pages".
    public let title: String
    /// For the one-line summary: "1 tab or page" / "8 tabs and pages".
    public let one: String
    public let many: String
    /// Largest first.
    public let members: [LiveProcess]

    public var id: String { title }
    public var totalBytes: Int64 { members.reduce(0) { $0 + $1.memoryBytes } }
    public var totalText: String { MemorySize.text(totalBytes) }

    func keeping(_ pids: Set<Int>) -> CensusPart? {
        let kept = members.filter { pids.contains($0.pid) }
        return kept.isEmpty ? nil
            : CensusPart(kind: kind, title: title, one: one, many: many, members: kept)
    }
}

extension StopTarget {
    /// The same program narrowed to some of its processes; nil when none remain.
    func keeping(_ pids: Set<Int>) -> StopTarget? {
        let kept = members.filter { pids.contains($0.pid) }
        return kept.isEmpty ? nil : StopTarget(id: id, identity: identity, name: name,
                                               whereItRuns: whereItRuns, lockedBy: lockedBy,
                                               canStop: canStop, members: kept,
                                               memberIdentities: memberIdentities.filter { pids.contains($0.pid) },
                                               isInteractiveShell: isInteractiveShell,
                                               hostedSessions: hostedSessions)
    }
}
