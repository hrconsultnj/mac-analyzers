import SwiftUI
import AnalyzersKit
import UIComponents

/// The needs-attention cards, shown only when true.
extension HomeSettingsView {

    // MARK: - needs attention (only renders what is actually true)

    @ViewBuilder var attentionSection: some View {
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
                                 subtitle: "Latest storage check — review before anything is deleted.",
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
}
