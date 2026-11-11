import SwiftUI
import AnalyzersKit
import UIComponents

/// What the latest storage check found it could reclaim, as a table.
struct ReclaimableNowDetailView: View {
    @State private var items: [StoragePathItem] = []
    @State private var loaded = false
    @State private var sortOrder = [KeyPathComparator(\StoragePathItem.sizeBytes, order: .reverse)]

    var body: some View {
        Group {
            if loaded && items.isEmpty {
                ContentUnavailableView("Nothing to Reclaim", systemImage: "sparkles",
                                       description: Text("The latest check found nothing a cleanup would remove."))
            } else {
                Table(items.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.cacheKind)
                    TableColumn("Project", value: \.project)
                    TableColumn("Size", value: \.sizeBytes) { item in
                        Text(ByteSize.format(item.sizeBytes)).monospacedDigit()
                    }
                    .width(min: 80, ideal: 100)
                }
            }
        }
        .navigationTitle(Names.Screen.cachesAndBuilds)
        .navigationSubtitle("What a cleanup would remove — nothing is deleted until you review it")
        .task { await awaitLoad({ TrendsModel.reclaimableNow() }) { items = $0; loaded = true } }
    }
}
