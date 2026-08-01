import SwiftUI
import AnalyzersKit
import UIComponents

// MARK: - INTEGRATION CONTRACT
//
// This file supplies the drill-down screens for the Trends pane but does NOT
// wire navigation itself — that's the caller's job. The shell must:
//   1. Own a `[TrendsRoute]` path (or fold TrendsRoute into its existing
//      route/history model) somewhere up the NavigationStack that contains
//      TrendsSettingsView. The tiles/rows in TrendsSettingsView already push
//      via `NavigationLink(value: TrendsRoute...)` — nothing else to change
//      there.
//   2. Attach `.navigationDestination(for: TrendsRoute.self) { trendsDestination($0) }`
//      on that stack.
//   3. Nothing else — `trendsDestination(_:)` is a @ViewBuilder that returns
//      the fully-built detail screen (PaneScaffold and all) for every case.

/// Push target for everything reachable from the Trends pane's tiles and
/// Repeat Offenders rows — each case carries the period the user had
/// selected so the pushed screen stays scoped to the same window.
enum TrendsRoute: Hashable {
    case kills(TrendsModel.Period)
    case spikes(TrendsModel.Period)
    case pressure(TrendsModel.Period)
    case cpuHogs(TrendsModel.Period)
    case memoryFreed(TrendsModel.Period)
    case diskReclaimed(TrendsModel.Period)
    case reclaimableNow(TrendsModel.Period)
    case offender(String, TrendsModel.Period)
}

@ViewBuilder
func trendsDestination(_ route: TrendsRoute) -> some View {
    switch route {
    case .kills(let period):
        GuardEventListDetailView(title: "Runaways Stopped", symbol: "xmark.octagon.fill", color: .red,
                                 caption: "Every kill in the \(period.label.lowercased()) window — newest first.",
                                 period: period, category: .killed)
    case .spikes(let period):
        GuardEventListDetailView(title: "Spikes Caught", symbol: "arrow.up.right", color: .orange,
                                 caption: "Every memory spike flagged in the \(period.label.lowercased()) window.",
                                 period: period, category: .spikes)
    case .pressure(let period):
        GuardEventListDetailView(title: "Pressure Alerts", symbol: "exclamationmark.triangle.fill", color: .orange,
                                 caption: "Cap-exceeded and system pressure events in the \(period.label.lowercased()) window.",
                                 period: period, category: .pressure)
    case .cpuHogs(let period):
        GuardEventListDetailView(title: "CPU Hogs Flagged", symbol: "cpu", color: .purple,
                                 caption: "Processes that sustained high CPU in the \(period.label.lowercased()) window.",
                                 period: period, category: .cpu)
    case .memoryFreed(let period):
        MemoryFreedDetailView(period: period)
    case .diskReclaimed(let period):
        DiskReclaimedDetailView(period: period)
    case .reclaimableNow(let period):
        ReclaimableNowDetailView(period: period)
    case .offender(let name, let period):
        OffenderDetailView(name: name, period: period)
    }
}

// MARK: - shared GuardEvent row styling (GuardLogView's house style)

private func eventSymbol(for event: GuardEvent) -> String {
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

private func eventColor(for event: GuardEvent) -> Color {
    switch event.kind {
    case .killed, .pressureCritical: .red
    case .spike, .capExceeded, .pressureWarning, .warning: .orange
    case .cpuHog, .forensics: .purple
    }
}

private func eventBadge(for event: GuardEvent) -> (String, Color)? {
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

private func eventTime(_ event: GuardEvent) -> String {
    event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
}

private func eventSubtitleWithTime(_ event: GuardEvent) -> String {
    event.subtitle.isEmpty ? eventTime(event) : "\(event.subtitle) · \(eventTime(event))"
}

/// "6144 MB" style numbers formatted the same way the rest of Trends does —
/// GB once it's over a gig, plain MB below that.
private func formatMB(_ mb: Int) -> String {
    mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
}

// MARK: - kills / spikes / pressure / cpuHogs

/// Generic drill-down for a single GuardEvent.Category: the same event list
/// GuardLogView shows, scoped to one period and one category.
private struct GuardEventListDetailView: View {
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
                    DataCard(symbol: eventSymbol(for: event), color: eventColor(for: event),
                             title: event.title,
                             subtitle: eventSubtitleWithTime(event),
                             trailing: event.residentText,
                             badge: eventBadge(for: event),
                             live: event.isProcessStillRunning)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let window = period
        let bucket = category
        detachedLoad({ TrendsModel.events(period: window, category: bucket) }) { events = $0 }
    }
}

// MARK: - memoryFreed

private struct MemoryFreedDetailView: View {
    let period: TrendsModel.Period

    @State private var entries: [MemoryFreedEntry] = []

    var body: some View {
        PaneScaffold(symbol: "memorychip", color: .blue, title: "Memory Freed",
                     caption: "Per-process memory recovered in the \(period.label.lowercased()) window — guard kills plus reap closures.") {
            Section {
                if entries.isEmpty {
                    Text("No memory freed in this window.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    DataCard(symbol: "memorychip", color: .blue,
                             title: entry.name,
                             trailing: formatMB(entry.freedMB))
                }
            }
        }
        .onAppear {
            let window = period
            detachedLoad({ TrendsModel.memoryFreedByProcess(period: window) }) { entries = $0 }
        }
    }
}

// MARK: - diskReclaimed

private struct DiskReclaimedDetailView: View {
    let period: TrendsModel.Period

    @State private var groups: [DiskReclaimedGroup] = []

    var body: some View {
        PaneScaffold(symbol: "internaldrive.fill", color: .indigo, title: "Disk Reclaimed",
                     caption: "Deleted build caches and node_modules in the \(period.label.lowercased()) window, grouped by project.") {
            if groups.isEmpty {
                Section {
                    Text("Nothing reclaimed in this window.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(groups) { group in
                Section {
                    DisclosureGroup {
                        ForEach(group.items) { item in
                            DataCard(symbol: "folder.fill", color: .indigo,
                                     title: item.cacheKind,
                                     subtitle: item.path,
                                     trailing: ByteSize.format(item.sizeBytes),
                                     badge: ("DELETED", .red))
                        }
                    } label: {
                        HStack {
                            IconTile(symbol: "folder.fill", color: .indigo)
                            Text(group.project).font(.callout.weight(.medium))
                            Spacer()
                            Text(ByteSize.format(group.totalBytes))
                                .font(.callout.monospacedDigit().weight(.semibold))
                        }
                    }
                }
            }
        }
        .onAppear {
            let window = period
            detachedLoad({ TrendsModel.diskReclaimedByProject(period: window) }) { groups = $0 }
        }
    }
}

// MARK: - reclaimableNow

private struct ReclaimableNowDetailView: View {
    let period: TrendsModel.Period

    @State private var items: [StoragePathItem] = []

    var body: some View {
        PaneScaffold(symbol: "sparkles", color: .teal, title: "Reclaimable Right Now",
                     caption: "The latest storage scan's dry-run findings — nothing deleted yet.") {
            Section {
                if items.isEmpty {
                    Text("Nothing reclaimable right now.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    DataCard(symbol: "folder.fill", color: .teal,
                             title: item.cacheKind,
                             subtitle: item.path,
                             trailing: ByteSize.format(item.sizeBytes),
                             badge: ("DRY", .blue))
                }
            }
        }
        .onAppear {
            detachedLoad({ TrendsModel.reclaimableNow() }) { items = $0 }
        }
    }
}

// MARK: - offender(name)

private struct OffenderDetailView: View {
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
                        DataCard(symbol: eventSymbol(for: event), color: eventColor(for: event),
                                 title: event.title,
                                 subtitle: eventSubtitleWithTime(event),
                                 trailing: event.residentText,
                                 badge: eventBadge(for: event),
                                 live: event.isProcessStillRunning)
                    }
                }
            }
        }
        .onAppear {
            let window = period
            let processName = name
            detachedLoad({ TrendsModel.offenderTimeline(name: processName, period: window) }) { timeline = $0 }
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
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
