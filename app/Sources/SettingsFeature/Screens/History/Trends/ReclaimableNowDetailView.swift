import SwiftUI
import AnalyzersKit
import UIComponents

/// What the latest storage check found it could reclaim, grouped under the project, app or tool each thing belongs
/// to (`StorageNaming`, the same words the Caches & Builds review uses), as the app's one table for rows that open.
struct ReclaimableNowDetailView: View {

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
    @State private var open = RememberedExpansion<String>(screen: "trends.reclaimable")

    /// A few groups holding a screenful of rows open on first sight; many closed.
    private static let openByDefault = 6
    private static let openRowLimit = 200

    var body: some View {
        Group {
            if loaded && rows.isEmpty {
                ContentUnavailableView("Nothing to Reclaim", systemImage: "sparkles",
                                       description: Text("The latest check found nothing a cleanup would remove."))
            } else {
                OutlineTable(sorted(rows), children: \.children, selection: $selection, sortOrder: $sortOrder,
                             expanded: open.binding, autosave: "trends.reclaimable") {
                    OutlineColumn("name", Names.Column.name, text: \.name,
                                  sortUsing: KeyPathComparator(\Row.name, comparator: .localizedStandard))
                    OutlineColumn("items", Names.Column.items, text: \.detail).textStyle { _ in .secondary }
                    OutlineColumn("size", Names.Column.size, text: { ByteSize.format($0.bytes) },
                                  sortUsing: KeyPathComparator(\Row.bytes))
                        .alignment(.trailing).monospacedDigits()
                        .width(min: 80, ideal: 100, max: 140)
                }
                .emptyContent(isLoading: !loaded) { EmptyView() }
            }
        }
        .navigationTitle(Names.Screen.cachesAndBuilds)
        .navigationSubtitle("What a cleanup would remove — nothing is deleted until you review it")
        .task {
            await awaitLoad({ TrendsModel.reclaimableNow() }) { found in
                rows = Dictionary(grouping: found, by: \.group).map { group, items in
                    Row(id: "group:" + group, name: group,
                        detail: "\(items.count) \(items.count == 1 ? "item" : "items")",
                        bytes: items.reduce(Int64(0)) { $0 + $1.sizeBytes },
                        children: items.map { Row(id: $0.id, name: $0.title, detail: "", bytes: $0.sizeBytes, children: nil) })
                }
                loaded = true
                let itemCount = found.count
                let few = rows.count <= Self.openByDefault && itemCount <= Self.openRowLimit
                open.seedIfUntouched(few ? Set(rows.map(\.id)) : [])
            }
        }
    }

    /// The caller sorts its own rows, each level by the chosen column.
    private func sorted(_ level: [Row]) -> [Row] {
        level.sorted(using: sortOrder).map { row in
            Row(id: row.id, name: row.name, detail: row.detail, bytes: row.bytes, children: row.children.map { sorted($0) })
        }
    }
}
