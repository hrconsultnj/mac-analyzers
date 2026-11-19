import SwiftUI
import AnalyzersKit
import AgentFeature
import UIComponents

/// Settings → Agents: which engine answers Ask, and the doors to the other
/// two agent screens (On-Device Models, Capabilities).
///
/// PHASE 1 SCAFFOLD: the engine cards (Sparehold On-Device, Claude Code, Codex,
/// bring-your-own) are Phase 3 (lane B) — this screen carries the navigation
/// and the engine pick's persistence until then. The scaffolding text below
/// is replaced wholesale by that phase; do not extend it.
struct AgentsScreen: View {
    @Environment(Navigator.self) private var navigator
    @Environment(ConfigStore.self) private var config

    var body: some View {
        PaneScaffold(symbol: "cpu", color: .mint, title: Names.Screen.agents,
                     caption: "Which engine answers Ask, and what it may do on this Mac.") {
            Section {
                engineRow(title: Names.Screen.onDeviceModels,
                          summary: "Download and choose the model that runs on this Mac.",
                          symbol: "internaldrive.fill") {
                    navigator.push(.settings(.onDeviceModels))
                }
                engineRow(title: Names.Screen.capabilities,
                          summary: "What the agent may do, and the extra instructions it always reads.",
                          symbol: "checkmark.shield.fill") {
                    navigator.push(.settings(.capabilities))
                }
            } header: {
                Text("The agent")
            }
            Section {
                Text("The engine cards — the model on this Mac, Claude Code, and Codex — arrive with the agent engines update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One row that opens another screen — the same shape the Settings hub uses
    /// for its preference screens.
    private func engineRow(title: String, summary: String, symbol: String,
                           action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: Tokens.Space.xl) {
                IconTile(symbol: symbol, color: .mint, side: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    Text(title)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.m)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
