import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory Guard log pane: full-depth structured events (the same parser the
/// menu and Activity use) behind filter chips with live counts — no raw text.
struct GuardLogView: View {

    /// Activity used to be a separate sidebar row rendering the SAME parser
    /// over the SAME file with a shorter window — one screen with a range
    /// switch replaces two screens that could disagree.
    enum Window: Hashable {
        case week, quarter
        var seconds: TimeInterval { self == .week ? 7 * 86_400 : 90 * 86_400 }
        var label: String { self == .week ? "Last 7 days" : "Last 90 days" }
    }

    @State private var window: Window = .quarter
    @State private var events: [GuardEvent] = []
    @State private var filter: GuardEvent.Category = .all
    @State private var search = ""

    private var filtered: [GuardEvent] {
        let byCategory = filter == .all ? events : events.filter { $0.category == filter }
        guard !search.isEmpty else { return byCategory }
        let needle = search.lowercased()
        return byCategory.filter {
            $0.friendlyName.lowercased().contains(needle)
                || $0.processName.lowercased().contains(needle)
                || ($0.pid.map { String($0).contains(needle) } ?? false)
        }
    }

    private func count(_ category: GuardEvent.Category) -> Int {
        category == .all ? events.count : events.filter { $0.category == category }.count
    }

    var body: some View {
        PaneScaffold(symbol: "shield.lefthalf.filled", color: .blue, title: "Memory Guard",
                     caption: "What the guard saw and did — pick a range, then filter by what matters.") {
            Section {
                FullWidthSegments(
                    options: [(Window.week, "Last 7 days"), (Window.quarter, "Last 90 days")],
                    selection: $window
                )
                HStack {
                    FilterChipsBar(
                        chips: GuardEvent.Category.allCases.map { cat in
                            .init(cat, cat.rawValue, count: count(cat), color: chipColor(cat))
                        },
                        selection: $filter
                    )
                    Spacer(minLength: 8)
                    Button("Open in TextEdit") { GuardControl.openLog(AnalyzersPaths.guardLog) }
                    Button {
                        load()
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                }
                TextField("Filter by process or pid…", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            Section {
                if filtered.isEmpty {
                    Text(events.isEmpty
                         ? "No guard events yet — quiet is good."
                         : "No \(filter.rawValue.lowercased()) in the loaded range.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { event in
                    row(for: event)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: window) { load() }
    }

    @ViewBuilder private func row(for event: GuardEvent) -> some View {
        if case .forensics(let path) = event.kind {
            // pushes the in-app forensics screen (stat cards + process table)
            NavigationLink(value: LogRoute.forensics(ForensicsRoute(path: path))) {
                DataCard(symbol: "stethoscope", color: .purple,
                         title: event.title,
                         subtitle: "\(event.subtitle) · \(time(event))",
                         badge: ("REPORT", .purple))
            }
        } else {
            DataCard(symbol: symbol(for: event), color: color(for: event),
                     title: event.title,
                     subtitle: subtitleWithTime(event),
                     trailing: event.residentText,
                     badge: badge(for: event),
                     live: event.isProcessStillRunning)
        }
    }

    // MARK: - styling maps

    private func subtitleWithTime(_ event: GuardEvent) -> String {
        event.subtitle.isEmpty ? time(event) : "\(event.subtitle) · \(time(event))"
    }

    private func time(_ event: GuardEvent) -> String {
        event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func chipColor(_ category: GuardEvent.Category) -> Color {
        switch category {
        case .all: .blue
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
        case .forensics: nil
        case .warning: ("WARN", .orange)
        }
    }

    private func load() {
        let span = window.seconds
        detachedLoad({
            GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog, within: span, limit: 500)
        }) { events = $0 }
    }
}
