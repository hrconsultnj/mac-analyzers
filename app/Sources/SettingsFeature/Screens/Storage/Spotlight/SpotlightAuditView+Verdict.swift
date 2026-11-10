import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Section 2: the stuck-versus-progressing verdict and the copyable manual commands.
extension SpotlightAuditView {

    // MARK: - section 2: verdict

    @ViewBuilder func verdictSection(_ run: SpotlightAuditRun) -> some View {
        Section("Stuck or progressing?") {
            DataCard(symbol: verdictSymbol(run.verdict), color: verdictColor(run.verdict),
                     title: verdictTitle(run.verdict),
                     subtitle: run.verdictDetail,
                     badge: (run.verdict.rawValue, verdictColor(run.verdict)))
            if let cmd = run.deepCheckCommand {
                commandRow("Deep check — the definitive signal", cmd)
            }
            if let cmd = run.rebuildCommand {
                commandRow("Only if genuinely stuck 24h+", cmd)
            }
            if !run.verdictRaw.isEmpty {
                rawBlock(run.verdictRaw)
            }
        }
    }

    private func commandRow(_ caption: String, _ cmd: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(cmd)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.chip))
                Button(copiedCommand == cmd ? "Copied ✓" : "Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                    copiedCommand = cmd
                }
                .controlSize(.small)
            }
        }
    }

    private func verdictTitle(_ verdict: SpotlightAuditRun.Verdict) -> String {
        switch verdict {
        case .progressing: "Progressing"
        case .idleOrComplete: "Idle or complete"
        case .notRunning: "Not running"
        case .unknown: "Unknown"
        }
    }

    private func verdictSymbol(_ verdict: SpotlightAuditRun.Verdict) -> String {
        switch verdict {
        case .progressing: "arrow.triangle.2.circlepath"
        case .idleOrComplete: "checkmark.circle"
        case .notRunning: "moon.zzz"
        case .unknown: "questionmark.circle"
        }
    }

    private func verdictColor(_ verdict: SpotlightAuditRun.Verdict) -> Color {
        switch verdict {
        case .progressing: .blue
        case .idleOrComplete: .green
        case .notRunning: .gray
        case .unknown: .secondary
        }
    }
}
