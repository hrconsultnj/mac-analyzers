import AnalyzersKit
import Foundation

/// One row of the outline: an app (a parent that opens to its programs) or a
/// single program. A `Table` holds one row type, so both are this.
struct NetworkNode: Identifiable, Hashable {
    let row: NetworkProcessRow?
    let group: NetworkGroup?

    var id: String { row?.id ?? group?.id ?? "" }
    var isGroup: Bool { row == nil }

    init(group: NetworkGroup) { self.group = group; row = nil }
    init(row: NetworkProcessRow) { self.row = row; group = nil }

    // sort keys: a KeyPathComparator needs plain Comparable properties
    var title: String { row?.name ?? group?.name ?? "" }
    var total: Int64 { row?.total ?? group?.total ?? 0 }
    var downloaded: Int64 { row?.downloaded ?? group?.downloaded ?? 0 }
    var uploaded: Int64 { row?.uploaded ?? group?.uploaded ?? 0 }
    var share: Double { row?.share ?? group?.share ?? 0 }
    var pidText: String { row.map { String($0.pid) } ?? "" }
    var pidValue: Int { row?.pid ?? 0 }
    var runningText: String { row.map(\.runningTitle) ?? group.map { "\($0.runningCount) of \($0.count)" } ?? "" }
    var kindText: String { row?.kindTitle ?? group?.countText ?? "" }
}
