import SwiftUI
import AnalyzersKit
import UIComponents

/// Disk space the storage cleaner deleted over one period, by project, as a
/// table that opens a project into what was removed.
struct DiskReclaimedDetailView: View {
    let period: TrendsModel.Period

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

    var body: some View {
        Group {
            if loaded && rows.isEmpty {
                ContentUnavailableView("Nothing Removed", systemImage: "internaldrive",
                                       description: Text("A cleanup has not deleted anything in this period."))
            } else {
                Table(rows.sorted(using: sortOrder), children: \.children, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Items") { row in Text(row.detail).foregroundStyle(.secondary) }
                    TableColumn("Removed", value: \.bytes) { row in
                        Text(ByteSize.format(row.bytes)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 110)
                }
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
                            Row(id: group.project + "/" + $0.id, name: $0.cacheKind, detail: "",
                                bytes: $0.sizeBytes, children: nil)
                        })
                }
                loaded = true
            }
        }
    }
}
