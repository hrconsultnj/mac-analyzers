import SwiftUI
import AnalyzersKit
import UIComponents

/// One kind of guard event over one period, as a table.
struct GuardEventListDetailView: View {
    let title: String
    let period: TrendsModel.Period
    let category: GuardEvent.Category

    @State private var rows: [OverviewModel.EventRow] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded { TrendsEventTable(rows: rows, emptyTitle: "No \(title)") } else { ProgressView() }
        }
        .navigationTitle(title)
        .navigationSubtitle(loaded ? "\(rows.count) in \(period.label.lowercased())" : period.label)
        .task {
            let window = period, bucket = category
            await awaitLoad({ OverviewModel.eventRows(TrendsModel.events(period: window, category: bucket), limit: Int.max) }) {
                rows = $0
                loaded = true
            }
        }
    }
}
