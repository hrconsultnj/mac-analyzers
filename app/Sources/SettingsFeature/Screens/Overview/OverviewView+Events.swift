import SwiftUI
import AnalyzersKit
import UIComponents

/// Recent guard events as named rows, and this week's totals.
extension OverviewView {

    func eventsBox(_ model: OverviewModel) -> some View {
        OverviewBox(title: "Recent Events", symbol: "clock") {
            if store.engine == nil {
                // the guard log has not been read yet: not the same as "nothing happened"
                ProgressView("Reading the guard log…").controlSize(.small)
            } else if model.events.isEmpty {
                if let cleared = OverviewModel.eventsClearedAt(), Date().timeIntervalSince(cleared) < 86_400 {
                    Text("You cleared this list at \(cleared.formatted(.dateTime.hour().minute())). Nothing new since.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No guard events in the last 24 hours — quiet is good.").foregroundStyle(.secondary)
                }
            }
            ForEach(model.events.prefix(4)) { row in
                OverviewRow(action: { navigator.open(target: "log:guardLog") }) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                            Text(row.outcome).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.when, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: row.event.symbol).foregroundStyle(row.event.tint)
                    }
                }
            }
            Divider()
            OverviewRow(action: { navigator.open(target: "logs") }) { Text("All \(Names.Screen.activity)") }
        }
    }

    @ViewBuilder var weekBox: some View {
        if let week {
            let totals = OverviewModel.Week(stopped: week.kills, alerts: week.spikes + week.pressure + week.cpuHogs,
                                            freedBytes: week.storageFreedBytes,
                                            memoryFreedMB: week.memoryFreedMB, runs: week.cleanRuns)
            OverviewBox(title: "This Week", symbol: "chart.xyaxis.line") {
                OverviewRow(action: { navigator.open(target: "trends:storage") }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(totals.summary)
                        Text("Open \(Names.Screen.trends) for the full story.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Share a one-page health report").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Export…") { HealthReport.save() }
                }
            }
        }
    }
}
