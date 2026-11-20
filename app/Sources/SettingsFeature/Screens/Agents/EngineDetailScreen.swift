import SwiftUI
import AnalyzersKit
import AgentFeature
import UIComponents

/// Which ACP engine a detail screen shows.
enum ACPVendor: Hashable, Sendable {
    case claude
    case codex

    var binaryName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var summary: String {
        switch self {
        case .claude: "Drives Anthropic's Claude through the official ACP adapter."
        case .codex: "Drives OpenAI's coding assistant through the official ACP adapter."
        }
    }

    var requires: String {
        switch self {
        case .claude: "Node.js and npx · the Claude Code CLI · your Claude subscription"
        case .codex: "Node.js and npx · the Codex CLI · ChatGPT account or OpenAI API key"
        }
    }

    var signInLine: String {
        switch self {
        case .claude: "Sign-in happens in Claude Code, never here. Open it in a terminal and sign in; Sparehold rides that login."
        case .codex: "Sign-in happens in Codex, never here. Open it in a terminal (ChatGPT account or API key); Sparehold rides that login."
        }
    }
}

/// One ACP engine's own screen: whether it is ready on this Mac, what it
/// needs, the vendor's own install command, and the switch that makes it the
/// engine Ask uses. Reached by pushing its row on the Agents screen —
/// cards that only display are not navigation.
struct EngineDetailScreen: View {
    let engine: ACPVendor
    @Environment(ConfigStore.self) private var config
    @State private var detection: EngineInstall.Detection?
    @State private var loaded = false

    var body: some View {
        PaneScaffold(symbol: "cpu", color: .mint, title: engine.title,
                     caption: engine.summary) {
            Section {
                statusRow
            } header: {
                Text("On this Mac")
            } footer: {
                Text(engine.signInLine)
            }
            Section {
                LabeledContent("Needs", value: engine.requires)
                if let path = detection?.binaryPath {
                    LabeledContent("Found at", value: path)
                }
                Button("Copy the official install command") { copyInstall() }
                    .help(EngineInstall.officialInstallCommand(forBinary: engine.binaryName))
            } header: {
                Text("What it needs")
            }
            Section {
                if isDefault {
                    Label("This is the engine Ask uses.", systemImage: "checkmark.circle")
                } else {
                    Button {
                        config.agent.engine = configAgentValue
                        try? config.save()
                    } label: {
                        Label("Use This Engine", systemImage: "star")
                    }
                }
            }
        }
        .onAppear {
            detection = EngineInstall.detect(vendorBinary: engine.binaryName)
            loaded = true
        }
    }

    private var configAgentValue: String {
        switch engine {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    private var isDefault: Bool {
        loaded && config.agent.engine == configAgentValue
    }

    @ViewBuilder private var statusRow: some View {
        if let detection {
            if detection.isReady {
                Label("Ready — version \(detection.version ?? "unknown").", systemImage: "checkmark.circle")
                    .foregroundStyle(Tokens.Status.safe.tint)
            } else {
                Label(detection.notReadySentence ?? "Not available yet.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(Tokens.Status.caution.tint)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func copyInstall() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(EngineInstall.officialInstallCommand(forBinary: engine.binaryName), forType: .string)
    }
}
