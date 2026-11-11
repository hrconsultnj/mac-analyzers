import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory recovered per process over one period, as a table.
struct MemoryFreedDetailView: View {
    let period: TrendsModel.Period

    @State private var entries: [MemoryFreedEntry] = []
    @State private var loaded = false
    @State private var sortOrder = [KeyPathComparator(\MemoryFreedEntry.freedMB, order: .reverse)]

    var body: some View {
        Group {
            if loaded && entries.isEmpty {
                ContentUnavailableView("No Memory Freed", systemImage: "memorychip",
                                       description: Text("Nothing was closed in this period."))
            } else {
                Table(entries.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Memory Freed", value: \.freedMB) { entry in
                        Text(formatMB(entry.freedMB)).monospacedDigit()
                    }
                    .width(min: 100, ideal: 120)
                }
            }
        }
        .navigationTitle("Memory Freed")
        .navigationSubtitle("Stopped by the guard or closed by a cleanup, \(period.label.lowercased())")
        .task {
            let window = period
            await awaitLoad({ TrendsModel.memoryFreedByProcess(period: window) }) {
                entries = $0
                loaded = true
            }
        }
    }
}
