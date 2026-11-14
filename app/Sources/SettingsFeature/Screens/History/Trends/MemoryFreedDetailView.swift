import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory recovered per process over one period, as a sortable table.
struct MemoryFreedDetailView: View {
    let period: ReportPeriod

    private struct Row: Identifiable {
        let id: String
        let name: String
        let freedMB: Int
        /// A flat table: nothing opens.
        var children: [Row]? { nil }
    }

    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var sortOrder = [KeyPathComparator(\Row.freedMB, order: .reverse)]
    @State private var selection: Set<String> = []
    @State private var open: Set<String> = []

    var body: some View {
        Group {
            if loaded && rows.isEmpty {
                EmptyState("No Memory Freed", systemImage: "memorychip",
                           description: Text("Nothing was closed in this period."))
            } else {
                OutlineTable(rows.sorted(using: sortOrder), children: \.children, selection: $selection,
                             sortOrder: $sortOrder, expanded: $open, autosave: "trends.memoryFreed") {
                    OutlineColumn("name", Names.Column.name, text: \.name,
                                  sortUsing: KeyPathComparator(\Row.name, comparator: .localizedStandard))
                    OutlineColumn("freed", Names.Column.memoryFreed, text: { formatMB($0.freedMB) },
                                  sortUsing: KeyPathComparator(\Row.freedMB))
                        .alignment(.trailing).monospacedDigits()
                        .width(min: 100, ideal: 120, max: 180)
                }
                .emptyContent(isLoading: !loaded) { EmptyView() }
            }
        }
        .navigationTitle("Memory Freed")
        .navigationSubtitle("Stopped by the guard or closed by a cleanup, \(period.phrase)")
        .task {
            let window = period
            await awaitLoad({ TrendsModel.memoryFreedByProcess(period: window) }, key: "trends.freed.\(window.rawValue)") {
                rows = $0.map { Row(id: $0.id, name: $0.name, freedMB: $0.freedMB) }
                loaded = true
            }
        }
    }
}
