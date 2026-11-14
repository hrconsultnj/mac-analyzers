import SwiftUI
import AnalyzersKit
import UIComponents

/// Disk space the storage cleaner deleted over one period, by project, as the
/// app's one table for rows that open: a project opens into what was removed.
/// The dashboard's project rows push this screen with their project opened and
/// selected, so the dashboard holds no second opening list over the same data.
struct DiskReclaimedDetailView: View {
    let period: TrendsModel.Period
    /// A project to open and select when the table first shows (from a dashboard row).
    var project: String?

    private struct Row: Identifiable {
        let id: String
        let name: String
        let detail: String
        let bytes: Int64
        let children: [Row]?
    }

    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var sortOrder = [KeyPathComparator(\Row.bytes, order: .reverse)]
    @State private var selection: Set<String> = []
    /// Which projects are open, kept across window close and relaunch.
    @State private var open = RememberedExpansion<String>(screen: "trends.removed")

    /// A few projects holding a screenful of rows open on first sight; many closed.
    private static let openByDefault = 6
    private static let openRowLimit = 200

    var body: some View {
        Group {
            if loaded && rows.isEmpty {
                EmptyState("Nothing Removed", systemImage: "internaldrive",
                                       description: Text("A cleanup has not deleted anything in this period."))
            } else {
                OutlineTable(sorted(rows), children: \.children, selection: $selection, sortOrder: $sortOrder,
                             expanded: open.binding, autosave: "trends.removed") {
                    OutlineColumn("name", Names.Column.name, text: \.name,
                                  sortUsing: KeyPathComparator(\Row.name, comparator: .localizedStandard))
                    OutlineColumn("items", Names.Column.items, text: \.detail).textStyle { _ in .secondary }
                    OutlineColumn("removed", Names.Column.removed, text: { ByteSize.format($0.bytes) },
                                  sortUsing: KeyPathComparator(\Row.bytes))
                        .alignment(.trailing).monospacedDigits()
                        .width(min: 90, ideal: 110, max: 160)
                }
                .emptyContent(isLoading: !loaded) { EmptyView() }
            }
        }
        .navigationTitle("Removed by Cleanups")
        .navigationSubtitle("Everything cleanups deleted, \(period.label.lowercased()), including folders that were rebuilt and removed again — not the net space gained")
        .task {
            let window = period
            await awaitLoad({ TrendsModel.diskReclaimedByProject(period: window) }) { groups in
                rows = groups.map { group in
                    Row(id: group.project, name: group.project,
                        detail: "\(group.items.count) \(group.items.count == 1 ? "item" : "items")",
                        bytes: group.totalBytes,
                        children: group.items.map {
                            Row(id: group.project + "/" + $0.id, name: $0.title, detail: "",
                                bytes: $0.sizeBytes, children: nil)
                        })
                }
                loaded = true
                let itemCount = rows.reduce(0) { $0 + ($1.children?.count ?? 0) }
                let few = rows.count <= Self.openByDefault && itemCount <= Self.openRowLimit
                open.seedIfUntouched(few ? Set(rows.map(\.id)) : [])
                if let project, rows.contains(where: { $0.id == project }) {
                    open.ids.insert(project)
                    selection = [project]
                }
            }
        }
    }

    /// The caller sorts its own rows, each level by the chosen column.
    private func sorted(_ level: [Row]) -> [Row] {
        level.sorted(using: sortOrder).map { row in
            Row(id: row.id, name: row.name, detail: row.detail, bytes: row.bytes,
                children: row.children.map { sorted($0) })
        }
    }
}
