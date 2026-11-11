import AnalyzersKit
import Foundation

/// The model half of level 3: the real-world thing rows belong to (a project, an app,
/// a day, a volume) as ONE group carrying its count and total. Rows that are nothing
/// (0 bytes) fold into a single closed group at the end ("N empty items"). The group
/// name comes from the row's own data, never from splitting a title.
///
///     let groups = RowGroup.make(rows, group: \.project, bytes: \.bytes)
///
/// Drawing is not here: rows that open belong in the shared outline table, not in a
/// `List` (a SwiftUI `List` with opening rows logs an AppKit warning on expand-all).
struct RowGroup<Row: Identifiable & Sendable>: Identifiable, Sendable where Row.ID: Sendable {
    let id: String
    let title: String
    let rows: [Row]
    let bytes: Int64?
    /// True for the one closed group of rows that are nothing.
    let isFolded: Bool

    static var emptyID: String { "fold:empty" }
    var count: Int { rows.count }

    /// "9 items · 96 KB".
    var summary: String {
        let noun = isFolded ? "empty item" : "item"
        let counted = "\(count) \(noun)\(count == 1 ? "" : "s")"
        guard let bytes else { return counted }
        return "\(counted) · \(ByteSize.format(bytes))"
    }

    /// Groups by the rows' own group name, biggest first when they have a size, with
    /// 0-byte rows folded at the end. A row naming no group stands alone.
    static func make(_ rows: [Row], group name: (Row) -> String?, bytes size: (Row) -> Int64?,
                     emptyTitle: String = "Empty Items") -> [RowGroup<Row>] {
        let sized = rows.contains { size($0) != nil }
        let empty = sized ? rows.filter { size($0) == 0 } : []
        let emptyIDs = Set(empty.map(\.id))
        let live = rows.filter { !emptyIDs.contains($0.id) }
        var order: [String] = []
        var buckets: [String: [Row]] = [:]
        for row in live {
            let key = name(row).map { "group:\($0)" } ?? "row:\(row.id)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(row)
        }
        var groups = order.map { key -> RowGroup<Row> in
            let members = buckets[key] ?? []
            let sizes = members.compactMap(size)
            return RowGroup(id: key, title: name(members[0]) ?? "",
                            rows: sized ? members.sorted { (size($0) ?? -1) > (size($1) ?? -1) } : members,
                            bytes: sizes.isEmpty ? nil : sizes.reduce(0, +), isFolded: false)
        }
        if sized { groups.sort { ($0.bytes ?? -1) > ($1.bytes ?? -1) } }
        if !empty.isEmpty {
            groups.append(RowGroup(id: emptyID, title: emptyTitle, rows: empty, bytes: 0, isFolded: true))
        }
        return groups
    }
}
