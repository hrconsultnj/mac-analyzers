import AnalyzersKit
import Foundation

/// One thing a review shows: what a person ticks or unticks, or — when `keptReason`
/// is set — what the cleanup will NOT touch, shown so the review is whole.
///
/// Each cleaner's screen turns its own typed rows (a storage path, a process, a
/// temp item) into these, so one table serves every review. `id` is the key the
/// kernel's `ApprovedSet` is built from — a path for files, a pid for processes —
/// and must be exactly the key the engine's preview listed.
struct ReviewRow: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    /// Under the name: the path, or who owns it. For a row that is chosen but gets a
    /// different action ("Will be asked to quit"), say so here; it is still a tick.
    var detail: String?
    /// The project or app the row belongs to; the table groups by it.
    var group: String?
    var bytes: Int64?
    /// A file or folder whose real Finder icon is shown beside the name.
    var iconPath: String?
    /// Set when the cleanup leaves this row alone: the reason, in words. Such a row has
    /// no working tick and never counts in the selection, Select All, the approved
    /// list or the confirmation.
    var keptReason: String?
    /// Shown in the size column when the row has no byte count (a time, "257 MB").
    var valueText: String?
    /// Set when the apply WILL act on this row although it is not ticked here (an app on the "also
    /// quit" list): the action in words ("Will be asked to quit"). Never counted as kept, never in
    /// the approved list; the bar counts it and the confirmation names it.
    var actsWord: String?

    init(id: String, name: String, detail: String? = nil, group: String? = nil, bytes: Int64? = nil,
         iconPath: String? = nil, keptReason: String? = nil, valueText: String? = nil, actsWord: String? = nil) {
        self.valueText = valueText
        self.actsWord = actsWord
        self.id = id
        self.name = name
        self.detail = detail
        self.group = group
        self.bytes = bytes
        self.iconPath = iconPath
        self.keptReason = keptReason
    }

    var isChoosable: Bool { keptReason == nil && actsWord == nil }
    var acts: Bool { actsWord != nil }

    /// Sort key for the size column (a row without a size sorts last).
    var sortBytes: Int64 { bytes ?? -1 }
}

/// One line of the review table: a thing, or a group of them that opens to its
/// members with its count and total. Built from the rows by `ReviewNode.tree`.
struct ReviewNode: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String?
    var bytes: Int64?
    var iconPath: String?
    var valueText: String?
    /// The keys a tick on this line sets: itself, or every CHOOSABLE member of a group.
    var rowIDs: [String]
    /// Members of a group; nil for a single thing, so the table shows no arrow.
    var children: [ReviewNode]?
    /// A row the cleanup leaves alone (its reason is `detail`), or a group of only those.
    var isKept: Bool
    /// A row the apply acts on without a tick here.
    var acts: Bool

    var isGroup: Bool { children != nil }
    var sortBytes: Int64 { bytes ?? -1 }
    var sortName: String { title }

    /// The fold's id can never equal a group's: groups are `group:<name>`.
    static let foldID = RowGroup<ReviewRow>.emptyID

    init(row: ReviewRow) {
        id = row.id; title = row.name; bytes = row.bytes; iconPath = row.iconPath; valueText = row.valueText
        isKept = row.keptReason != nil
        acts = row.acts
        // a kept row says why, an acting row says what will happen, where a chosen one says where
        // it is; the path stays in the tooltip
        detail = row.keptReason ?? row.actsWord ?? row.detail
        rowIDs = row.isChoosable ? [row.id] : []
        children = nil
    }

    init(group title: String, id: String, members: [ReviewNode]) {
        self.id = id
        self.title = title
        let sizes = members.compactMap(\.bytes)
        bytes = sizes.isEmpty ? nil : sizes.reduce(0, +)
        let kept = members.filter(\.isKept).count
        let counted = "\(members.count) \(members.count == 1 ? "item" : "items")"
        detail = kept > 0 && kept < members.count ? "\(counted) · \(kept) kept" : counted
        iconPath = nil
        valueText = nil
        rowIDs = members.flatMap(\.rowIDs)
        isKept = kept == members.count
        acts = false
        children = members
    }

    /// The tree for these rows, grouped and folded by `RowGroup.make` (one rule, one fold):
    /// groups with something to choose come first and groups with nothing to choose last;
    /// the fold of rows that are nothing is closed at the very end; a row that names no
    /// group stays flat.
    static func tree(_ rows: [ReviewRow], order: [KeyPathComparator<ReviewNode>]) -> [ReviewNode] {
        var top: [ReviewNode] = []
        var fold: ReviewNode?
        for group in RowGroup.make(rows, group: \.group, bytes: \.bytes, emptyTitle: Names.Fold.empty) {
            let members = group.rows.map(ReviewNode.init(row:)).sorted(using: order)
            if group.isFolded {
                fold = ReviewNode(group: group.title, id: foldID, members: members)
            } else if group.id.hasPrefix("row:"), let only = members.first {
                top.append(only)
            } else {
                top.append(ReviewNode(group: group.title, id: group.id, members: members))
            }
        }
        let sorted = top.sorted(using: order)
        return sorted.filter { !$0.isKept } + sorted.filter(\.isKept) + (fold.map { [$0] } ?? [])
    }
}
