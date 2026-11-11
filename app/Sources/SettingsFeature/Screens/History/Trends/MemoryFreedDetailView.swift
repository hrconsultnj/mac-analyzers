import SwiftUI
import AnalyzersKit
import UIComponents

struct MemoryFreedDetailView: View {
    let period: TrendsModel.Period

    @State private var entries: [MemoryFreedEntry] = []

    var body: some View {
        PaneScaffold(symbol: "memorychip", color: .blue, title: "Memory Freed",
                     caption: "Per-process memory recovered in the \(period.label.lowercased()) window — guard kills plus reap closures.") {
            Section {
                if entries.isEmpty {
                    Text("No memory freed in this window.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    DataCard(symbol: "memorychip", color: .blue,
                             title: entry.name,
                             trailing: formatMB(entry.freedMB))
                }
            }
        }
        .task {
            let window = period
            await awaitLoad({ TrendsModel.memoryFreedByProcess(period: window) }) { entries = $0 }
        }
    }
}
