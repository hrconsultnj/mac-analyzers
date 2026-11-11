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
        public let processCount: Int
        public let category: CensusGroup.Category
        public let canQuit: Bool
        /// Quitting is an app's ⌘Q; otherwise it is a polite stop for tools.
        public let isApp: Bool
        public let group: CensusGroup
    }

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
        processes = groups.prefix(limit).map { group in
            let detail: String?
            if group.members.count > 1 {
                detail = group.partsSummary ?? "\(group.members.count) processes"
            } else {
                detail = group.role
            }
            let quit: Bool
            if case .unavailable = group.quit { quit = false } else { quit = true }
            let app: Bool
            if case .app = group.quit { app = true } else { app = false }
            return ProcessRow(id: group.id, name: group.name, totalBytes: group.totalBytes,
                              sizeText: group.totalText, detail: detail,
                              processCount: group.members.count, category: group.category,
                              canQuit: quit, isApp: app, group: group)
        }
    }
}
