import SwiftUI
import AnalyzersKit
import UIComponents

/// Activity pane: the last ~50 guard events over 7 days, with the same human
/// titles the menu uses. Same PaneScaffold as every other pane — it displays
/// and scrolls identically to Memory/Storage/Notifications.
struct ActivitySettingsView: View {
    @State private var events: [GuardEvent] = []

    var body: some View {
        PaneScaffold(symbol: "list.bullet.rectangle.fill", color: .orange, title: "Activity",
                     caption: "Everything the memory guard did or flagged in the last 7 days.") {
            Section {
                HStack {
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open guard log") { GuardControl.openLog(AnalyzersPaths.guardLog) }
                    Button {
                        load()
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                }
            }
            Section {
                if events.isEmpty {
                    Text("No events in the last 7 days.")
                        .foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(event.title)
                                .foregroundStyle(event.isKill ? Color.red : .orange)
                            if !event.subtitle.isEmpty {
                                Text(event.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 4)
                        if let live = event.isProcessStillRunning {
                            LiveStateChip(active: live)
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        detachedLoad({
            GuardLogParser.recentEvents(fromLog: AnalyzersPaths.guardLog,
                                        within: 7 * 86_400, limit: 50)
        }) { events = $0 }
    }
}
