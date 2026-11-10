import SwiftUI
import AnalyzersKit
import UIComponents

/// Generic drill-down for a single GuardEvent.Category: the same event list
/// GuardLogView shows, scoped to one period and one category.
struct GuardEventListDetailView: View {
    let title: String
    let symbol: String
    let color: Color
    let caption: String
    let period: TrendsModel.Period
    let category: GuardEvent.Category

    @State private var events: [GuardEvent] = []

    var body: some View {
        PaneScaffold(symbol: symbol, color: color, title: title, caption: caption) {
            Section {
                if events.isEmpty {
                    Text("Nothing in this window.")
                        .foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    DataCard(symbol: event.symbol, color: event.tint,
                             title: event.title,
                             subtitle: eventSubtitleWithTime(event),
                             trailing: event.residentText,
                             badge: event.badge,
                             live: event.isProcessStillRunning)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let window = period
        let bucket = category
        await awaitLoad({ TrendsModel.events(period: window, category: bucket) }) { events = $0 }
    }
}
