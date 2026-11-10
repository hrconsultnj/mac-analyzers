import SwiftUI
import AnalyzersKit
import UIComponents

struct OffenderDetailView: View {
    let name: String
    let period: TrendsModel.Period

    @State private var timeline: OffenderTimeline?

    var body: some View {
        PaneScaffold(symbol: "flame.fill", color: .orange, title: name,
                     caption: "Full event timeline in the \(period.label.lowercased()) window.") {
            if let timeline {
                Section {
                    statRow(timeline)
                }
                Section {
                    if timeline.events.isEmpty {
                        Text("No events in this window.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(timeline.events) { event in
                        DataCard(symbol: event.symbol, color: event.tint,
                                 title: event.title,
                                 subtitle: eventSubtitleWithTime(event),
                                 trailing: event.residentText,
                                 badge: event.badge,
                                 live: event.isProcessStillRunning)
                    }
                }
            }
        }
        .task {
            let window = period
            let processName = name
            await awaitLoad({ TrendsModel.offenderTimeline(name: processName, period: window) }) { timeline = $0 }
        }
    }

    private func statRow(_ t: OffenderTimeline) -> some View {
        HStack(spacing: 10) {
            statTile("\(t.eventCount)", "Events", .blue)
            statTile("\(t.killCount)", "Kills", .red)
            statTile(t.peakResidentMB > 0 ? formatMB(t.peakResidentMB) : "—", "Peak resident", .purple)
        }
        .padding(.vertical, 2)
    }

    private func statTile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
    }
}
