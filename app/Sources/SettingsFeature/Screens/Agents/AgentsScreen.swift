import SwiftUI
import AnalyzersKit
import AgentFeature
import UIComponents

/// Settings › Agents: which engine answers Ask. One card per engine — the
/// model on this Mac, the person's own Claude Code, Codex, or a custom
/// command — with a radio to make one the default. The vendor's binary owns
/// the login: sign-in happens in Claude Code / Codex, never here, and the
/// cards say so. Every card states its Requires line before install, and an
/// install runs the vendor's own official command (copied for Terminal), never
/// a silent download.
struct AgentsScreen: View {
    @Environment(Navigator.self) private var navigator
    @Environment(ConfigStore.self) private var config
    /// The engine detections, probed once on appear (`--version` spawns a
    /// process; never from the body).
    @State private var detections: [String: EngineInstall.Detection] = [:]
    @State private var installed = InstalledModels.shared
    @State private var loaded = false

    var body: some View {
        PaneScaffold(symbol: "cpu", color: .mint, title: Names.Screen.agents,
                     caption: "Which engine answers Ask, and what it may do on this Mac.") {
            Section {
                engineCard(
                    id: "on-device", symbol: "internaldrive.fill",
                    name: "Sparehold On-Device", badge: "on-device · local",
                    summary: "Runs the model downloaded in On-Device Models on this Mac. Nothing leaves.",
                    requires: "a downloaded on-device model · sufficient memory",
                    ready: onDeviceReady, readyLine: onDeviceLine) {
                    navigator.push(.settings(.onDeviceModels))
                } choose: { choose("on-device") }
            } header: {
                Text("Built in")
            } footer: {
                Text("Answers offline, and file names never leave this Mac.")
            }

            Section {
                acpCard(id: "claude", symbol: "chevron.left.forwardslash.chevron.right",
                        name: "Claude Code",
                        summary: "Drives Anthropic's Claude through the official ACP adapter.",
                        requires: "Node.js and npx · the Claude Code CLI · your Claude subscription — sign-in happens in Claude Code, never here")
                acpCard(id: "codex", symbol: "curlybraces.square",
                        name: "Codex",
                        summary: "Drives OpenAI's coding assistant through the official ACP adapter.",
                        requires: "Node.js and npx · the Codex CLI · ChatGPT account or OpenAI API key — sign-in happens in Codex, never here")
            } header: {
                Text("Tested with Sparehold")
            } footer: {
                Text("The vendor's own binary holds the login. Sparehold supervises every step and never sees a token.")
            }

            Section {
                TextEditor(text: customCommandBinding)
                    .frame(minHeight: 56)
                    .onChange(of: config.agent.customCommand) { _, _ in
                        guard loaded else { return }
                        try? config.save()
                    }
            } header: {
                Text("Bring your own")
            } footer: {
                Text("A command Sparehold runs and supervises the same way. Never point it at something you don't trust.")
            }
        }
        .onAppear {
            installed.reload()
            for binary in ["claude", "codex"] {
                detections[binary] = EngineInstall.detect(vendorBinary: binary)
            }
            loaded = true
        }
    }

    // MARK: - the built-in card

    private var onDeviceReady: Bool {
        !config.agent.modelID.isEmpty && installed.installed(config.agent.modelID) != nil
    }

    private var onDeviceLine: String {
        if let model = installed.installed(config.agent.modelID) {
            return "Active model: \(model.id) (\(ByteSize.text(model.sizeBytes, .headline)) on disk)."
        }
        if let first = installed.models.first {
            return "Downloaded: \(first.id). Choose it on the models screen."
        }
        return "No model downloaded yet."
    }

    // MARK: - the ACP cards

    private func acpCard(id: String, symbol: String, name: String, summary: String, requires: String) -> some View {
        let detection = detections[id == "claude" ? "claude" : "codex"]
        return engineCard(
            id: id, symbol: symbol,
            name: name, badge: detection?.version,
            summary: summary,
            requires: requires,
            ready: detection?.isReady == true, readyLine: detection?.notReadySentence ?? "Ready.") {
        } choose: {
            choose(id)
        }
    }

    // MARK: - shared card shape

    private func engineCard(id: String, symbol: String, name: String, badge: String?, summary: String,
                            requires: String, ready: Bool, readyLine: String,
                            action: @escaping () -> Void,
                            choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.m) {
                IconTile(symbol: symbol, color: .mint, side: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(name).font(.headline)
                        if let badge { Text(badge).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.m)
            }
            Group {
                if ready {
                    Label(readyLine, systemImage: "checkmark.circle").font(.caption)
                } else {
                    Label(readyLine, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(Tokens.Status.caution.tint)
                }
            }
            Text("**Requires:** \(requires)").font(.caption).foregroundStyle(.secondary)
            HStack {
                if config.agent.engine == id {
                    BadgeCapsule(text: "DEFAULT ENGINE", color: Tokens.Status.safe.tint)
                } else {
                    Button("Use This Engine") { choose() }.controlSize(.small)
                }
                if id == "on-device" {
                    Button(actionTitle, action: action).controlSize(.small)
                } else if let binary = id == "claude" ? "claude" : "codex", detections[binary]?.binaryPath == nil {
                    Button("Copy Install Command") { copyInstall(binary) }.controlSize(.small)
                        .help(EngineInstall.officialInstallCommand(forBinary: binary))
                }
            }
        }
        .padding(Tokens.Space.s)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
        .accessibilityElement(children: .contain)
    }

    private var actionTitle: String { "Choose a Model" }

    private func choose(_ id: String) {
        config.agent.engine = id
        try? config.save()
    }

    private func copyInstall(_ binary: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(EngineInstall.officialInstallCommand(forBinary: binary), forType: .string)
    }

    private var customCommandBinding: Binding<String> {
        Binding(
            get: { config.agent.customCommand },
            set: { config.agent.customCommand = $0 })
    }
}
