import SwiftUI
import AnalyzersKit
import UIComponents

/// Where the space is: free space, temp on disk, disk images, agent folders.
extension TempSpaceView {

    // MARK: - overview

    @ViewBuilder func overviewSection(_ run: TempCleanRun) -> some View {
        Section("Where the Space Is") {
            if let free = run.freeSpace {
                DataCard(symbol: "internaldrive", color: .blue,
                         title: "Free Space", subtitle: "on this Mac's disk", trailing: free)
            }
            DataCard(symbol: "tray.full", color: .mint,
                     title: "Temp on Disk", subtitle: "/tmp, your temp folder and /var/tmp",
                     trailing: run.tempOnDisk)
            if let inside = run.insideImagesBytes, inside > 0 {
                DataCard(symbol: "opticaldiscdrive", color: .purple,
                         title: "Inside Mounted Disk Images",
                         subtitle: "Not on your disk — a plain du would report \(run.plainDu ?? "more")",
                         trailing: run.insideImages)
            }
            DataCard(symbol: "sparkles", color: .orange,
                     title: "AI Agent Folders", subtitle: agentSubtitle(run),
                     trailing: run.agentFolders)
            DataCard(symbol: "checkmark.circle", color: .green,
                     title: "Ready to Clear",
                     subtitle: run.readyItems.isEmpty
                         ? "Nothing qualifies right now"
                         : "\(run.readyItems.reduce(0) { $0 + $1.count }) item(s) — review and untick in Actions",
                     trailing: ByteSize.format(run.readyBytes))
            if let rules = run.rulesLine {
                Text(rules)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let selfClean = run.selfCleanLine {
                Text(selfClean)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func agentSubtitle(_ run: TempCleanRun) -> String {
        var parts: [String] = []
        if let n = run.liveClaudeSessions { parts.append("\(n) live Claude Code session\(n == 1 ? "" : "s")") }
        if let codex = run.codexRunning { parts.append(codex ? "Codex running" : "Codex closed") }
        if let claude = run.claudeAppRunning { parts.append(claude ? "Claude app running" : "Claude app closed") }
        return parts.isEmpty ? "Claude Code, Codex, Claude app, npx tools" : parts.joined(separator: " · ")
    }
}
