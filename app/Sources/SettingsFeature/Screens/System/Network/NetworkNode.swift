import AppKit
import AnalyzersKit
import SwiftUI
import UIComponents

/// One row of the outline: an app (a parent that opens to its programs) or a
/// single program. A program that works alone is that program as a plain row,
/// not a group of one: this model decides it, the table only draws what it is given.
struct NetworkNode: Identifiable, Hashable {
    let row: NetworkProcessRow?
    let group: NetworkGroup?
    /// The programs of an app of two or more; nil for a program (and for a lone one).
    let children: [NetworkNode]?

    var id: String { row?.id ?? group?.id ?? "" }
    var isGroup: Bool { row == nil }

    init(group: NetworkGroup, sort: [KeyPathComparator<NetworkNode>]) {
        self.group = group
        row = nil
        children = group.rows.map(NetworkNode.init(row:)).sorted(using: sort)
    }

    init(row: NetworkProcessRow) {
        self.row = row
        group = nil
        children = nil
    }

    /// The rows of a snapshot, sorted at both levels; an app with one program is that program.
    static func tree(_ groups: [NetworkGroup], sort: [KeyPathComparator<NetworkNode>]) -> [NetworkNode] {
        groups.map { group in
            group.count == 1 ? NetworkNode(row: group.rows[0]) : NetworkNode(group: group, sort: sort)
        }
        .sorted(using: sort)
    }

    // sort keys and the words of each cell: a KeyPathComparator needs plain Comparable properties
    var title: String { row?.name ?? group?.name ?? "" }
    var total: Int64 { row?.total ?? group?.total ?? 0 }
    var downloaded: Int64 { row?.downloaded ?? group?.downloaded ?? 0 }
    var uploaded: Int64 { row?.uploaded ?? group?.uploaded ?? 0 }
    var share: Double { row?.share ?? group?.share ?? 0 }
    var pidText: String { row.map { String($0.pid) } ?? "" }
    var pidValue: Int { row?.pid ?? 0 }
    var runningText: String { row.map(\.runningTitle) ?? group.map { "\($0.runningCount) of \($0.count)" } ?? "" }
    var kindText: String { row?.kindTitle ?? "" }
    var totalText: String { ByteSize.format(total) }
    var downloadedText: String { ByteSize.format(downloaded) }
    var uploadedText: String { ByteSize.format(uploaded) }
    var shareText: String { share.formatted(.percent.precision(.fractionLength(0))) }

    /// The icon of a program (its app's own while it runs), or of an app's first program, at row size.
    var iconImage: Image {
        let first = row ?? group?.rows.first
        if let first, first.isRunning, let icon = NSRunningApplication(processIdentifier: pid_t(first.pid))?.icon {
            let sized = (icon.copy() as? NSImage) ?? icon
            sized.size = NSSize(width: 16, height: 16)   // an app icon is drawn at its own size: that is its job
            return Image(nsImage: sized)
        }
        return Image(systemName: "gearshape")
    }
}

/// The Name cell: a program's icon and name, or an app's icon, name and count.
struct NetworkNodeName: View {
    let node: NetworkNode

    var body: some View {
        if let group = node.group {
            OutlineGroupCell(name: group.name, summary: group.countText, icon: node.iconImage)
        } else {
            Label { Text(node.title) } icon: { node.iconImage }
        }
    }
}
