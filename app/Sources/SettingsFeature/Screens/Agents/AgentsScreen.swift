import SwiftUI
import AnalyzersKit
import AgentFeature
import UIComponents

/// Settings › Agents: which engine answers Ask. Rows that PUSH — the same
/// stack navigation as the Settings hub — each carrying its one-line status;
/// the detail screen holds the switches and the vendor guidance. The vendor's
/// binary owns the login: sign-in happens in Claude Code / Codex, never here.
struct AgentsScreen: View {
    @Environment(Navigator.self) private var navigator
    @Environment(ConfigStore.self) private var config
    @State private var installed = InstalledModels.shared

    var body: some View {
        PaneScaffold(symbol: "cpu", color: .mint, title: Names.Screen.agents,
                     caption: "Which engine answers Ask, and what it may do on this Mac.") {
            Section {
                agentRow(
                    symbol: "internaldrive.fill",
                    title: Names.Screen.onDeviceModels,
                    summary: onDeviceSummary,
                    isDefault: config.agent.engine == "on-device") {
                    navigator.push(.settings(.onDeviceModels))
                }
                agentRow(
                    symbol: "chevron.left.forwardslash.chevron.right",
                    title: "Claude Code",
                    summary: "Your Claude subscription, through the official adapter. Sign-in happens in Claude Code, never here.",
                    isDefault: config.agent.engine == "claude") {
                    navigator.push(.settings(.engineClaude))
                }
                agentRow(
                    symbol: "curlybraces.square",
                    title: "Codex",
                    summary: "ChatGPT account or OpenAI API key, through the official adapter. Sign-in happens in Codex, never here.",
                    isDefault: config.agent.engine == "codex") {
                    navigator.push(.settings(.engineCodex))
                }
            } header: {
                Text("Engines")
            } footer: {
                Text("The vendor's own binary holds the login. Sparehold supervises every step and never sees a token.")
            }
            Section {
                TextEditor(text: customCommandBinding)
                    .frame(minHeight: 56)
                    .onChange(of: config.agent.customCommand) { _, _ in
                        try? config.save()
                    }
            } header: {
                Text("Bring your own")
            } footer: {
                Text("A command Sparehold runs and supervises the same way. Never point it at something you don't trust.")
            }
        }
        .onAppear { installed.reload() }
    }

    private var onDeviceSummary: String {
        if let model = installed.installed(config.agent.modelID) {
            return "Active model \(model.id) — runs entirely on this Mac, nothing leaves."
        }
        if !installed.models.isEmpty {
            return "\(installed.models.count) downloaded. Choose the active one on the models screen."
        }
        return "Download a model and Ask runs entirely on this Mac — nothing leaves, works offline."
    }

    /// One row that pushes — the hub's own row shape (IconTile, summary,
    /// chevron), plus the default-engine mark so the choice reads at a glance.
    private func agentRow(symbol: String, title: String, summary: String,
                          isDefault: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: Tokens.Space.xl) {
                IconTile(symbol: symbol, color: .mint, side: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(title)
                        if isDefault { BadgeCapsule(text: "DEFAULT ENGINE", color: Tokens.Status.safe.tint) }
                    }
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Tokens.Space.m)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customCommandBinding: Binding<String> {
        Binding(
            get: { config.agent.customCommand },
            set: { config.agent.customCommand = $0 })
    }
}
