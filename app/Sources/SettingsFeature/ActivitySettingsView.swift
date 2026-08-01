import SwiftUI
import AnalyzersKit
import UIComponents

/// Activity pane: the last 7 days of guard events with the SAME treatment
/// its sibling GuardLogView has — counted filter chips, DataCard rows,
/// liveness chips (QA fix: this pane had been left as plain text rows).
struct ActivitySettingsView: View {
    @State private var events: [GuardEvent] = []
    @State private var filter: GuardEvent.Category = .all

    private var filtered: [GuardEvent] {
        filter == .all ? events : events.filter { $0.category == filter }
    }

    private func count(_ category: GuardEvent.Category) -> Int {
        category == .all ? events.count : events.filter { $0.category == category }.count
    }

    var body: some View {
        PaneScaffold(symbol: "list.bullet.rectangle.fill", color: .orange, title: "Activity",
                     caption: "Everything the memory guard did or flagged in the last 7 days.") {
            Section {
                HStack {
                    FilterChipsBar(
                        chips: GuardEvent.Category.allCases.map { cat in
                            .init(cat, cat.rawValue, count: count(cat), color: chipColor(cat))
                        },
                        selection: $filter
                    )
                    Spacer(minLength: 8)
                    Button("Open guard log") { GuardControl.openLog(AnalyzersPaths.guardLog) }
                    Button {
                        load()
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                }
            }
            Section {
                if filtered.isEmpty {
                    Text(events.isEmpty
                         ? "No events in the last 7 days."
                         : "No \(filter.rawValue.lowercased()) in the last 7 days.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { event in
                    DataCard(symbol: symbol(for: event), color: color(for: event),
                             title: event.title,
                             subtitle: event.subtitle.isEmpty
                                 ? time(event)
                                 : "\(event.subtitle) · \(time(event))",
                             trailing: event.residentText,
                             badge: badge(for: event),
                             live: event.isProcessStillRunning)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func time(_ event: GuardEvent) -> String {
        event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func chipColor(_ category: GuardEvent.Category) -> Color {
        switch category {
        case .all: .orange
        case .spikes: .orange
        case .killed: .red
        case .reports: .purple
        case .pressure: .orange
        case .cpu: .purple
        }
    }

    private func symbol(for event: GuardEvent) -> String {
        switch event.kind {
        case .killed: "xmark.octagon.fill"
        case .spike: "arrow.up.right"
        case .capExceeded: "gauge.with.needle"
        case .pressureWarning, .pressureCritical: "exclamationmark.triangle.fill"
        case .cpuHog: "cpu"
        case .forensics: "stethoscope"
        case .warning: "exclamationmark.triangle"
        }
    }

    private func color(for event: GuardEvent) -> Color {
        switch event.kind {
        case .killed, .pressureCritical: .red
        case .spike, .capExceeded, .pressureWarning, .warning: .orange
        case .cpuHog, .forensics: .purple
        }
    }

    private func badge(for event: GuardEvent) -> (String, Color)? {
        switch event.kind {
        case .killed: ("KILLED", .red)
        case .spike: ("SPIKE", .orange)
        case .capExceeded: ("OVER CAP", .orange)
        case .pressureWarning: ("PRESSURE", .orange)
        case .pressureCritical: ("CRITICAL", .red)
        case .cpuHog: ("CPU", .purple)
        case .forensics: ("REPORT", .purple)
        case .warning: ("WARN", .orange)
        }
    }

    private func load() {
        detachedLoad({
            // allEvents, not recentEvents: the caption promises EVERYTHING in
            // seven days, while the menu parser deliberately collapses
            // clutter (drops spikes for later-killed pids, caps at 50).
            GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog,
                                     within: 7 * 86_400, limit: 500)
        }) { events = $0 }
    }
}
