import Foundation

/// What the menu-bar panel lists as processes: the same groups, names and
/// footprint numbers Monitor shows (the memory census), the biggest first, with
/// no size floor — so the panel and Monitor cannot disagree about who is using
/// memory. (The panel used to read resident size above 256 MB.)
public struct MenuPanelModel: Sendable {

    public struct ProcessRow: Identifiable, Sendable {
        public let id: String
        /// "Opera", "Next.js dev server".
        public let name: String
        public let totalBytes: Int64
        public let sizeText: String
        /// "11 helpers", "tabs and pages, extensions", or what a macOS service is for.
        public let detail: String?
        /// The full breakdown ("2 tabs and pages, 13 extensions, 2 for graphics"), for hover; Monitor shows it in full.
        public let breakdown: String?
        public let processCount: Int
        public let category: CensusGroup.Category
        public let canQuit: Bool
        /// Quitting is an app's ⌘Q; otherwise it is a polite stop for tools.
        public let isApp: Bool
        public let group: CensusGroup
    }

    /// One row of the panel's Monitor tab: a group (an app, a tool, a macOS service) or, below it, one of its members.
    /// The same groups and names Monitor shows; a group opens to its parts (an app) or its separate programs (a tool).
    public struct Node: Identifiable, Sendable {
        public let id: String
        public let name: String
        /// One short phrase: "3 helpers", "36 processes", or what a macOS service is for.
        public let detail: String?
        /// The full breakdown for hover ("2 tabs and pages, 13 extensions, …"); Monitor shows it in full.
        public let breakdown: String?
        public let sizeText: String
        public let category: CensusGroup.Category
        /// The Monitor row this belongs to, by its exact name (`MemoryStop.monitorLink(forGroup:)`).
        public let groupName: String
        /// What Quit or Stop acts on: set on a group, never on a member.
        public let group: CensusGroup?
        /// For a member: the group it belongs to, for its icon (an app's parts take the app's, smaller).
        public let owner: CensusGroup?
        public let children: [Node]?
    }

    /// How many groups the table lists before "N more in Monitor".
    public static let nodesPerTab = 30

    /// The Monitor tab for one category (nil is All), heaviest first, at most `nodesPerTab` groups, and how many more
    /// there are. Members are built only for the groups shown.
    public func nodes(in category: CensusGroup.Category?) -> (nodes: [Node], more: Int) {
        let mine = category == nil ? allGroups : allGroups.filter { $0.category == category }
        let shown = mine.prefix(Self.nodesPerTab)
        return (shown.map(Self.node), mine.count - shown.count)
    }

    /// Groups, processes and bytes per category, for the tabs' counts.
    public func groupCount(in category: CensusGroup.Category?) -> Int {
        category == nil ? allGroups.count : allGroups.filter { $0.category == category }.count
    }

    private let allGroups: [CensusGroup]

    public let processes: [ProcessRow]
    /// Everything the census found, for "N more".
    public let totalGroups: Int
    public let totalBytes: Int64
    /// Physical memory in use, and in all, for a summary line (nil when the Mac would not say).
    public let memoryUsedBytes: Int64?
    public let memoryTotalBytes: Int64?
    public init(census: MemoryCensus, limit: Int = 8) {
        let groups = census.groups
        totalGroups = groups.count
        totalBytes = census.totalBytes
        memoryUsedBytes = census.breakdown?.usedBytes
        memoryTotalBytes = census.breakdown?.totalBytes
        allGroups = groups
        processes = groups.prefix(limit).map(Self.row)
    }

    private static func node(_ group: CensusGroup) -> Node {
        let row = Self.row(group)
        // an app opens to its parts, a tool to its separate programs; one of them is not worth an arrow
        var members: [Node] = []
        if group.category == .apps, group.parts.count > 1 {
            members = group.parts.map { part in
                Node(id: "\(group.id)|part|\(part.id)", name: part.title,
                     detail: part.members.count > 1 ? "\(part.members.count) processes" : nil, breakdown: nil,
                     sizeText: part.totalText, category: group.category, groupName: group.name, group: nil, owner: group, children: nil)
            }
        } else if group.category == .tools, group.programs.count > 1 {
            members = group.programs.map { program in
                Node(id: "\(group.id)|program|\(program.id)", name: program.label,
                     detail: program.members.count > 1 ? "\(program.members.count) processes" : nil, breakdown: nil,
                     sizeText: program.totalText, category: group.category, groupName: group.name, group: nil, owner: group, children: nil)
            }
        }
        return Node(id: group.id, name: group.name, detail: row.detail, breakdown: row.breakdown, sizeText: group.totalText,
                    category: group.category, groupName: group.name, group: group, owner: nil,
                    children: members.isEmpty ? nil : members)
    }

    private static func row(_ group: CensusGroup) -> ProcessRow {
        // one short phrase: the count, or what a macOS service is for; the breakdown is on hover and in Monitor
        let detail: String?
        if group.members.count > 1 {
            let others = group.members.count - 1
            detail = group.category == .apps ? "\(others) \(others == 1 ? "helper" : "helpers")" : "\(group.members.count) processes"
        } else {
            // what a macOS service is for, when it is short; a long sentence is on hover and in Monitor
            detail = group.role.flatMap { $0.count <= 24 ? $0 : nil }
        }
        let quit: Bool
        if case .unavailable = group.quit { quit = false } else { quit = true }
        let app: Bool
        if case .app = group.quit { app = true } else { app = false }
        return ProcessRow(id: group.id, name: group.name, totalBytes: group.totalBytes,
                          sizeText: group.totalText, detail: detail,
                          breakdown: group.members.count > 1 ? group.partsSummary : group.role,
                          processCount: group.members.count, category: group.category,
                          canQuit: quit, isApp: app, group: group)
    }
}
