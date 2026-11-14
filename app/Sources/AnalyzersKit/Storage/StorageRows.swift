import Foundation

/// A tab of a Storage screen: a kind of thing, with its name and its symbol. The
/// raw value is what a deep link (`caches:projects`) and the remembered tab use.
public protocol StorageCategory: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    var title: String { get }
    var symbol: String { get }
}

/// A tab built from data, for a screen whose tabs are not a fixed list (Old Recordings: one tab per recording source the
/// person has). Its raw value is the tab's id, which a row carries as its `category`, the remembered tab and a deep link
/// use. Two tabs are the same tab when their ids are.
public struct StorageTab: StorageCategory {
    public let rawValue: String
    public let title: String
    public let symbol: String

    public init(id: String, title: String, symbol: String) {
        rawValue = id
        self.title = title
        self.symbol = symbol
    }

    /// A tab known only by its id (the remembered tab, read back): the screen matches it to a real one by id.
    public init?(rawValue: String) { self.init(id: rawValue, title: rawValue, symbol: "folder") }

    /// A tab built from data has no fixed list.
    public static var allCases: [StorageTab] { [] }

    public static func == (lhs: StorageTab, rhs: StorageTab) -> Bool { lhs.rawValue == rhs.rawValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
}

/// One thing a Storage review or a finished run shows, in the shape every Storage
/// screen shares: its tab (`category`), the real thing it belongs to (`group`: a
/// project, an app, an agent, an age), and what it is called for a person. Built
/// by each screen's review from its parser; nothing is recovered from a title.
public struct StorageRow: Identifiable, Hashable, Sendable {
    /// The engine's own key: a path, or `prune:<id>`. What the reviewed list holds.
    public let id: String
    /// A `StorageCategory` raw value.
    public let category: String
    public let group: String?
    public let title: String
    /// Under the title: the path and when it was used, or what happened to it.
    public let detail: String?
    public let bytes: Int64?
    /// Shown in the size column when there are no bytes.
    public let valueText: String?
    /// The file whose Finder icon is drawn; nil for a row that is not a file.
    public let iconPath: String?
    /// Set when the cleanup leaves the row alone: why, in words.
    public let keptReason: String?

    public init(id: String, category: String, group: String?, title: String, detail: String? = nil,
                bytes: Int64? = nil, valueText: String? = nil, iconPath: String? = nil, keptReason: String? = nil) {
        self.id = id
        self.category = category
        self.group = group
        self.title = title
        self.detail = detail
        self.bytes = bytes
        self.valueText = valueText
        self.iconPath = iconPath
        // a key the reviewed list cannot carry is never offered for a tick (`ApprovedSet.isListable`)
        self.keptReason = keptReason ?? (ApprovedSet.isListable(id) ? nil : ApprovedSet.unlistableReason)
    }

    public var isChoosable: Bool { keptReason == nil }
}

/// A set of rows with what each tab holds.
public struct StorageRows: Sendable {
    public let rows: [StorageRow]
    /// Result lines that are not rows (Time Machine, projects in use), said over the review.
    public let notes: [String]
    /// Short facts for the subtitle ("free space 122.5 GB").
    public let facts: [String]
    /// Sentences that belong to one tab only (a category's `rawValue`), said over that tab.
    public let tabNotes: [String: [String]]
    /// The tabs, when they come from data instead of a screen's enum: in the order to show them. Nil for the screens
    /// whose `StorageCategory` lists them.
    public let dataTabs: [StorageTab]?

    public init(_ rows: [StorageRow], notes: [String] = [], facts: [String] = [], tabNotes: [String: [String]] = [:],
                tabs: [StorageTab]? = nil) {
        self.rows = rows
        self.notes = notes
        self.facts = facts
        self.tabNotes = tabNotes
        self.dataTabs = tabs
    }

    /// The tabs to show: those with rows, from the data when the screen has data tabs, else from its `StorageCategory`.
    public func tabs<C: StorageCategory>(_ type: C.Type) -> [StorageTab] {
        if let dataTabs { return dataTabs.filter { count(inTab: $0.rawValue) > 0 } }
        return filled(type).map { StorageTab(id: $0.rawValue, title: $0.title, symbol: $0.symbol) }
    }

    public func rows(inTab id: String) -> [StorageRow] { rows.filter { $0.category == id } }
    public func count(inTab id: String) -> Int { rows(inTab: id).count }
    /// What is said over one tab: the notes for the whole review, then that tab's own.
    public func notes(forTab id: String) -> [String] { notes + (tabNotes[id] ?? []) }

    /// What is said over a tab: the notes for the whole review, then the tab's own.
    public func notes<C: StorageCategory>(for category: C) -> [String] { notes + (tabNotes[category.rawValue] ?? []) }

    public func rows<C: StorageCategory>(in category: C) -> [StorageRow] { rows.filter { $0.category == category.rawValue } }
    public func count<C: StorageCategory>(in category: C) -> Int { rows(in: category).count }
    public func bytes<C: StorageCategory>(in category: C) -> Int64 {
        rows(in: category).reduce(0) { $0 + ($1.bytes ?? 0) }
    }
    /// The categories that have rows, in declaration order.
    public func filled<C: StorageCategory>(_ type: C.Type) -> [C] { C.allCases.filter { count(in: $0) > 0 } }
    /// The keys a review can offer for a tick: every choosable row.
    public var choosable: [StorageRow] { rows.filter(\.isChoosable) }
    public var choosableBytes: Int64 { choosable.reduce(0) { $0 + ($1.bytes ?? 0) } }
    public var totalBytes: Int64 { rows.reduce(0) { $0 + ($1.bytes ?? 0) } }
}

/// A run's block, found once for every Storage screen and result view: by banner
/// (a job's own run, whole, however big) or the newest preview in a log.
public enum StorageLog {

    /// The newest preview in the log of `kind`, whole.
    public static func newestPreview(of kind: JobKind) -> WholeRun.Block? {
        guard let url = kind.log?.url, case .block(let block) = WholeRun.newestPreview(in: url) else { return nil }
        return block
    }

    /// A given run, whole. `notBefore` is the job's start, for banners that repeat.
    public static func block(banner: String, of kind: JobKind, notBefore: Date? = nil) -> WholeRun.Block? {
        guard let url = kind.log?.url, case .block(let block) = WholeRun.find(banner: banner, in: url, notBefore: notBefore)
        else { return nil }
        return block
    }

    /// "~/Projects/site/.next": a path as a person writes it.
    public static func short(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory()) ? "~" + path.dropFirst(NSHomeDirectory().count) : path
    }

    /// "3 weeks ago".
    public static func ago(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
