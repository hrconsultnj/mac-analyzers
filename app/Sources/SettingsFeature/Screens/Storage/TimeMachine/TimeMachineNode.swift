import AnalyzersKit
import Foundation

/// One line of the Time Machine table: a day (a group with its count) or one local snapshot in it.
struct TimeMachineNode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String?
    /// "Thinned", "Couldn't Thin", or empty.
    let status: String
    var children: [TimeMachineNode]?

    var isGroup: Bool { children != nil }

    /// The days in the order the review gave them (newest first), each holding its snapshots.
    static func tree(_ rows: StorageRows) -> [TimeMachineNode] {
        var order: [String] = []
        var byGroup: [String: [StorageRow]] = [:]
        for row in rows.rows {
            let group = row.group ?? ""
            if byGroup[group] == nil { order.append(group) }
            byGroup[group, default: []].append(row)
        }
        return order.map { group in
            let members = byGroup[group] ?? []
            let leaves = members.map { row in
                TimeMachineNode(id: row.id, title: row.title, detail: row.keptReason ?? row.detail,
                                status: row.valueText ?? (row.keptReason == nil ? "" : "Kept"), children: nil)
            }
            let counted = "\(leaves.count) \(leaves.count == 1 ? "snapshot" : "snapshots")"
            return TimeMachineNode(id: "day:\(group)", title: group, detail: counted, status: "", children: leaves)
        }
    }
}
