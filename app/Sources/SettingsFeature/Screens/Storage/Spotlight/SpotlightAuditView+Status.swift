import SwiftUI
import AnalyzersKit
import UIComponents

/// Section 1: whether Spotlight indexing is on and how it is going.
extension SpotlightAuditView {

    // MARK: - section 1: indexing status

    @ViewBuilder func statusSection(_ run: SpotlightAuditRun) -> some View {
        Section("Indexing Status") {
            DataCard(symbol: statusSymbol(run), color: statusColor(run),
                     title: run.indexingLine ?? "Indexing status unknown",
                     subtitle: run.mdsLine.map { "mds/mdworker: \($0)" })
            if let update = run.recentUpdateLine {
                DataCard(symbol: "arrow.triangle.2.circlepath", color: .purple,
                         title: "Recent macOS Update", subtitle: update)
            }
            if !run.statusRaw.isEmpty {
                rawBlock(run.statusRaw)
            }
        }
    }

    private func statusSymbol(_ run: SpotlightAuditRun) -> String {
        indexingDisabled(run) ? "xmark.shield" : "checkmark.shield"
    }

    private func statusColor(_ run: SpotlightAuditRun) -> Color {
        indexingDisabled(run) ? .red : .green
    }

    private func indexingDisabled(_ run: SpotlightAuditRun) -> Bool {
        run.indexingLine?.lowercased().contains("disabled") ?? false
    }
}
