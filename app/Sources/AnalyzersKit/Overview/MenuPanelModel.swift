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

    /// One category of the census as the panel's Monitor tab shows it: the same grouping Monitor uses (the
    /// census's own category of each group), with how many apps or tools it holds and their total, the heaviest first.
    public struct Section: Identifiable, Sendable {
        public let category: CensusGroup.Category
        public let title: String
        public let symbol: String
        public let groups: Int
        public let processes: Int
        public let totalBytes: Int64
        public let totalText: String
        public let rows: [ProcessRow]
        /// Groups of the category that are not in `rows`.
        public let more: Int
        public var id: String { category.rawValue }
    }

    /// How many rows each category shows before "N more in Monitor".
    public static let rowsPerCategory: [CensusGroup.Category: Int] = [.apps: 5, .tools: 4, .system: 3]

    public let processes: [ProcessRow]
    /// The census by category, in the order Monitor's tabs run (apps, tools, macOS); empty categories left out.
    public let sections: [Section]
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
        processes = groups.prefix(limit).map(Self.row)
        sections = CensusGroup.Category.allCases.compactMap { category in
            let mine = groups.filter { $0.category == category }
            guard !mine.isEmpty else { return nil }
            let shown = mine.prefix(Self.rowsPerCategory[category] ?? 4)
            let bytes = mine.reduce(Int64(0)) { $0 + $1.totalBytes }
            return Section(category: category, title: category.shortTitle, symbol: category.symbol, groups: mine.count,
                           processes: mine.reduce(0) { $0 + $1.members.count }, totalBytes: bytes,
                           totalText: MemorySize.text(bytes), rows: shown.map(Self.row), more: mine.count - shown.count)
        }
    }

    private static func row(_ group: CensusGroup) -> ProcessRow {
        // one short phrase: the count, or what a macOS service is for; the breakdown is on hover and in Monitor
        let detail: String?
        if group.members.count > 1 {
            let others = group.members.count - 1
            detail = group.category == .apps ? "\(others) \(others == 1 ? "helper" : "helpers")" : "\(group.members.count) processes"
        } else {
            detail = group.role
        }
        let quit: Bool
        if case .unavailable = group.quit { quit = false } else { quit = true }
        let app: Bool
        if case .app = group.quit { app = true } else { app = false }
        return ProcessRow(id: group.id, name: group.name, totalBytes: group.totalBytes,
                          sizeText: group.totalText, detail: detail,
                          breakdown: group.members.count > 1 ? group.partsSummary : nil,
                          processCount: group.members.count, category: group.category,
                          canQuit: quit, isApp: app, group: group)
    }
}
