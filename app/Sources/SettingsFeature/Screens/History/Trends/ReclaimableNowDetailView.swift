import SwiftUI
import AnalyzersKit
import UIComponents

struct ReclaimableNowDetailView: View {
    let period: TrendsModel.Period

    @State private var items: [StoragePathItem] = []

    var body: some View {
        PaneScaffold(symbol: "sparkles", color: .teal, title: "Reclaimable Right Now",
                     caption: "The latest storage scan's dry-run findings — nothing deleted yet.") {
            Section {
                if items.isEmpty {
                    Text("Nothing reclaimable right now.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    DataCard(symbol: "folder.fill", color: .teal,
                             title: item.cacheKind,
                             subtitle: item.path,
                             trailing: ByteSize.format(item.sizeBytes),
                             badge: ("DRY", .blue))
                }
            }
        }
        .task {
            await awaitLoad({ TrendsModel.reclaimableNow() }) { items = $0 }
        }
    }
}
