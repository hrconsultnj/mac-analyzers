import Foundation

/// A tab of a Storage screen: a kind of thing, with its name and its symbol. The
/// raw value is what a deep link (`caches:projects`) and the remembered tab use.
public protocol StorageCategory: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    var title: String { get }
    var symbol: String { get }
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

    public init(_ rows: [StorageRow], notes: [String] = [], facts: [String] = [], tabNotes: [String: [String]] = [:]) {
        self.rows = rows
        self.notes = notes
        self.facts = facts
        self.tabNotes = tabNotes
    }

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
