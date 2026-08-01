import SwiftUI
import AnalyzersKit
import UIComponents

/// The Overview dashboard — landing screen behind the sidebar brand card.
/// Answers three questions in order: am I okay right now (status tiles),
/// what needs me (contextual attention cards, shown only when true), and
/// what's been happening (live processes, activity, trends teaser). Every
/// element drills into its own full screen via the internal router.
struct HomeSettingsView: View {

    @Environment(GuardLogStore.self) private var store
    @State private var trends: TrendsSnapshot?
    @State private var latestRelease: String?
    @State private var runway: ForecastModel.Runway?

    var body: some View {
        PaneScaffold(symbol: "macwindow.on.rectangle", color: .blue, title: "Overview",
                     caption: "Your Mac at a glance — click anything to go deeper.") {
            statusSection
            attentionSection
            processesSection
            activitySection
            trendsSection
        }
        .onAppear {
            store.reload()
            detachedLoad({ TrendsModel.snapshot(period: .day7) }) { trends = $0 }
            detachedLoad({ ForecastModel.diskRunway() }) { runway = $0 }
            Task {
                if let latest = await UpdateChecker.latestVersion() {
                    latestRelease = latest
                }
            }
        }
    }

    // MARK: - status tiles

    private var statusSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                      spacing: 10) {
                statTile(symbol: "memorychip", color: pressureColor,
                         value: store.pressure.label,
                         label: "Memory pressure", target: "monitor")
                statTile(symbol: guardSymbol, color: guardColor,
                         value: store.engine?.summary ?? "Checking…",
                         label: guardLabel,
                         target: "activity")
                statTile(symbol: "internaldrive.fill", color: diskColor,
                         value: store.disk.map { "\($0.freeText) free" } ?? "—",
                         label: runway.map { "runway \($0.text) at current pace" }
                             ?? store.disk.map { "of \($0.totalText) used \($0.usedText)" }
                             ?? "Disk",
                         target: "storage")
            }
            .padding(.vertical, 2)
        }
    }

    /// Three honest states, from what launchd actually reports — the tile
    /// used to show green "Active" purely because a pause file was absent,
    /// so a Mac with nothing installed looked protected.
    private var guardSymbol: String {
        guard let engine = store.engine else { return "shield.lefthalf.filled" }
        if !engine.isFullyInstalled { return "shield.slash" }
        if engine.guardPaused { return "pause.circle.fill" }
        if !engine.guardProcessRunning { return "exclamationmark.triangle.fill" }
        return "shield.lefthalf.filled"
    }

    private var guardColor: Color {
        guard let engine = store.engine else { return .secondary }
        if !engine.isFullyInstalled { return .orange }
        if engine.guardPaused || !engine.guardProcessRunning { return .orange }
        return .green
    }

    private var guardLabel: String {
        guard let engine = store.engine else { return "Guard" }
        if !engine.isFullyInstalled { return "Guard · not set up yet" }
        if engine.guardPaused { return "Guard · taking no action" }
        if !engine.guardProcessRunning { return "Guard · loaded but not running" }
        return store.killsToday == 1 ? "Guard · 1 stop today"
                                     : "Guard · \(store.killsToday) stops today"
    }

    private var pressureColor: Color {
        switch store.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private var diskColor: Color {
        guard let disk = store.disk else { return .indigo }
        return disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.75 ? .orange : .indigo
    }

    private func statTile(symbol: String, color: Color, value: String,
                          label: String, target: String) -> some View {
        Button {
            openPane(target)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.body)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - needs attention (only renders what is actually true)

    @ViewBuilder private var attentionSection: some View {
        let updateReady = latestRelease.map {
            UpdateChecker.isNewer($0, than: UpdateChecker.installedVersion)
        } ?? false
        let reclaimable = trends?.latestReclaimableBytes ?? 0
        let pressureBad = store.pressure != .normal

        let throttling = ThermalWatcher.shared.isElevated

        if updateReady || store.guardPaused || reclaimable > 1 << 30 || pressureBad || throttling {
            Section("Needs attention") {
                if throttling {
                    attentionRow(symbol: "thermometer.high", color: .red,
                                 title: "Your Mac is throttling to cool down",
                                 subtitle: "macOS is slowing the CPU — see who's working it hardest.",
                                 action: "Open Monitor", target: "monitor")
                }
                if pressureBad {
                    attentionRow(symbol: "exclamationmark.triangle.fill", color: .orange,
                                 title: "Memory pressure is \(store.pressure.label.lowercased())",
                                 subtitle: "See what's using RAM right now.",
                                 action: "Open Monitor", target: "monitor")
                }
                if store.guardPaused {
                    HStack {
                        DataCard(symbol: "pause.circle.fill", color: .orange,
                                 title: "Memory Guard is paused",
                                 subtitle: "Nothing is watching for runaways.")
                        Button("Resume") {
                            try? store.setGuardPaused(false)
                        }
                    }
                }
                if updateReady, let latestRelease {
                    attentionRow(symbol: "arrow.down.circle.fill", color: .green,
                                 title: "Update available — v\(latestRelease)",
                                 subtitle: "You're on v\(UpdateChecker.installedVersion).",
                                 action: "Open Update", target: "update")
                }
                if reclaimable > 1 << 30 {
                    attentionRow(symbol: "sparkles", color: .teal,
                                 title: "\(ByteSize.format(reclaimable)) reclaimable right now",
                                 subtitle: "Latest storage dry run — review before anything is deleted.",
                                 action: "Review", target: "log:storageClean")
                }
                if let runway, runway.urgent {
                    attentionRow(symbol: "chart.line.downtrend.xyaxis", color: .red,
                                 title: "Disk full in \(runway.text) at the current pace",
                                 subtitle: "Trend from your own storage-clean history.",
                                 action: "Free space", target: "actions:storageClean")
                }
            }
        }
    }

    private func attentionRow(symbol: String, color: Color, title: String,
                              subtitle: String, action: String, target: String) -> some View {
        HStack {
            DataCard(symbol: symbol, color: color, title: title, subtitle: subtitle)
            Button(action) { openPane(target) }
        }
    }

    // MARK: - live processes

    private var processesSection: some View {
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

    private var activitySection: some View {
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

    // MARK: - trends teaser

    @ViewBuilder private var trendsSection: some View {
        if let trends {
            Section {
                Button {
                    openPane("trends")
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trends.headline)
                                .font(.callout.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Open Trends for the full story.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack {
                    Text("Share a one-page health report")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export…") { HealthReport.save() }
                }
            } header: {
                Text("This week")
            }
        }
    }

    // MARK: - routing

    private func seeAllRow(_ title: String, target: String) -> some View {
        Button {
            openPane(target)
        } label: {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openPane(_ target: String) {
        NotificationCenter.default.post(name: NotifyChannel.openPaneInternal,
                                        object: nil, userInfo: ["target": target])
    }
}
