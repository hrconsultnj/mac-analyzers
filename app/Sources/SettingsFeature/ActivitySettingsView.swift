import SwiftUI
import AnalyzersKit

/// Activity tab: the bigger logger — the last ~50 guard events over 7 days,
/// with the same human titles the menu uses. Read-only view over guard.log.
struct ActivitySettingsView: View {
    @State private var events: [GuardEvent] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(events.count) event\(events.count == 1 ? "" : "s") in the last 7 days")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open guard log") { GuardControl.openLog(AnalyzersPaths.guardLog) }
                Button {
                    load()
                } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
            }
            .controlSize(.small)

            List(events) { event in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title)
                            .font(.callout)
                            .foregroundStyle(event.isKill ? .red : .orange)
                        if !event.subtitle.isEmpty {
                            Text(event.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowSeparator(.visible)
            }
        }
        .padding(12)
        .onAppear(perform: load)
    }

    private func load() {
        events = GuardLogParser.recentEvents(
            fromLog: AnalyzersPaths.guardLog,
            within: 7 * 86_400,
            limit: 50
        )
    }
}
