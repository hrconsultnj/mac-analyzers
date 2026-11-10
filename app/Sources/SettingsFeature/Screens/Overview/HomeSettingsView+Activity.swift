import SwiftUI
import AnalyzersKit
import UIComponents

/// Live processes and the recent guard events.
extension HomeSettingsView {

    // MARK: - live processes

    var processesSection: some View {
        Section {
            if store.topProcesses.isEmpty {
                Text("Nothing over the reporting floor right now.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.topProcesses.prefix(4)) { proc in
                ProcessRow(proc: proc) { store.reload() }
            }
            seeAllRow("Open Monitor", target: "monitor")
        } header: {
            Text("Biggest processes right now")
        }
    }

    // MARK: - recent activity

    var activitySection: some View {
        Section {
            if store.events.isEmpty {
                Text("No guard events today — quiet is good.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.events.prefix(4)) { event in
                DataCard(symbol: event.isKill ? "xmark.octagon.fill" : "arrow.up.right",
                         color: event.isKill ? .red : .orange,
                         title: event.title,
                         subtitle: event.subtitle.isEmpty
                             ? event.date.formatted(.dateTime.hour().minute())
                             : "\(event.subtitle) · \(event.date.formatted(.dateTime.hour().minute()))",
                         trailing: event.residentText,
                         live: event.isProcessStillRunning)
            }
            seeAllRow("All activity", target: "activity")
        } header: {
            Text("Recent events")
        }
    }
}
