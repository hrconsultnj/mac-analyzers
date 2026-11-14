import SwiftUI
import AnalyzersKit
import UIComponents

/// One kind of guard event over one period, as a table.
struct GuardEventListDetailView: View {
    let title: String
    let period: ReportPeriod
    let category: GuardEvent.Category

    @State private var rows: [OverviewModel.EventRow] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded { TrendsEventTable(rows: rows, emptyTitle: "No \(title)") } else { LoadingState() }
        }
        .navigationTitle(title)
        .navigationSubtitle(loaded ? "\(rows.count) in \(period.phrase)" : periodSubtitle(loading: period, ""))
        .task {
            let window = period, bucket = category
            await awaitLoad({ OverviewModel.eventRows(TrendsModel.events(period: window, category: bucket), limit: Int.max) },
                            key: "trends.events.\(window.rawValue).\(bucket.rawValue)") {
                rows = $0
                loaded = true
            }
        }
    }
}
