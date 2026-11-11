import SwiftUI
import AnalyzersKit
import UIComponents

/// What the latest storage check found it could reclaim, as a sortable table.
struct ReclaimableNowDetailView: View {

    private struct Row: Identifiable {
        let id: String
        let name: String
        let project: String
        let bytes: Int64
        /// A flat table: nothing opens.
        var children: [Row]? { nil }
    }

    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var sortOrder = [KeyPathComparator(\Row.bytes, order: .reverse)]
    @State private var selection: Set<String> = []
    @State private var open: Set<String> = []

    var body: some View {
        Group {
            if loaded && rows.isEmpty {
                ContentUnavailableView("Nothing to Reclaim", systemImage: "sparkles",
                                       description: Text("The latest check found nothing a cleanup would remove."))
            } else {
                OutlineTable(rows.sorted(using: sortOrder), children: \.children, selection: $selection,
                             sortOrder: $sortOrder, expanded: $open, autosave: "trends.reclaimable") {
                    OutlineColumn("name", Names.Column.name, text: \.name,
                                  sortUsing: KeyPathComparator(\Row.name, comparator: .localizedStandard))
                    OutlineColumn("project", Names.Column.project, text: \.project,
                                  sortUsing: KeyPathComparator(\Row.project, comparator: .localizedStandard))
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
            await awaitLoad({ TrendsModel.reclaimableNow() }) {
                rows = $0.map { Row(id: $0.id, name: $0.cacheKind, project: $0.project, bytes: $0.sizeBytes) }
                loaded = true
            }
        }
    }
}
