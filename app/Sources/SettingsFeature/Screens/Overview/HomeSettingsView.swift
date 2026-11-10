import SwiftUI
import AnalyzersKit
import UIComponents

/// The Overview dashboard — landing screen behind the sidebar brand card.
/// Answers three questions in order: am I okay right now (status tiles),
/// what needs me (contextual attention cards, shown only when true), and
/// what's been happening (live processes, activity, trends teaser). Every
/// element drills into its own full screen via the internal router.
///
/// This file is the screen's state and its composition. One job per file next to it:
///   HomeSettingsView+Status.swift          The status tiles: memory pressure, the guard and the disk.
///   HomeSettingsView+Attention.swift       The needs-attention cards, shown only when true.
///   HomeSettingsView+Activity.swift        Live processes and the recent guard events.
///   HomeSettingsView+Trends.swift          The trends teaser.
struct HomeSettingsView: View {

    @Environment(GuardLogStore.self) var store
    @State var trends: TrendsSnapshot?
    @State var latestRelease: String?
    @State var runway: ForecastModel.Runway?

    var body: some View {
        PaneScaffold(symbol: "macwindow.on.rectangle", color: .blue, title: "Overview",
                     caption: "Your Mac at a glance — click anything to go deeper.") {
            statusSection
            attentionSection
            processesSection
            activitySection
            trendsSection
        }
        .task {
            store.reload()
            await awaitLoad({ TrendsModel.snapshot(period: .day7) }) { trends = $0 }
            await awaitLoad({ ForecastModel.diskRunway() }) { runway = $0 }
            Task {
                if let latest = await UpdateChecker.latestVersion() {
                    latestRelease = latest
                }
            }
        }
    }

    // MARK: - routing

    func seeAllRow(_ title: String, target: String) -> some View {
        Button {
            openPane(target)
        } label: {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true) // decorative disclosure arrow — the row's own text says where it goes
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func openPane(_ target: String) {
        NotificationCenter.default.post(name: NotifyChannel.openPaneInternal,
                                        object: nil, userInfo: ["target": target])
    }
}
