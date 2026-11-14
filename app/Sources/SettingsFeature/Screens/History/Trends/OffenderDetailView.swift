import SwiftUI
import AnalyzersKit
import UIComponents

/// One process's whole guard timeline over one period, as a table.
struct OffenderDetailView: View {
    let name: String
    let period: TrendsModel.Period

    @State private var timeline: OffenderTimeline?

    var body: some View {
        Group {
            if let timeline {
                TrendsEventTable(rows: OverviewModel.eventRows(timeline.events, limit: Int.max),
                                 emptyTitle: "No Events")
            } else {
                LoadingState()
            }
        }
        .navigationTitle(name)
        .navigationSubtitle(subtitle)
        .task {
            let window = period, processName = name
            await awaitLoad({ TrendsModel.offenderTimeline(name: processName, period: window) }) { timeline = $0 }
        }
    }

    private var subtitle: String {
        guard let t = timeline else { return period.label }
        let peak = t.peakResidentMB > 0 ? ", peak \(formatMB(t.peakResidentMB))" : ""
        return "\(t.eventCount) \(t.eventCount == 1 ? "event" : "events"), \(t.killCount) stopped\(peak)"
    }
}
