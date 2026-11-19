import SwiftUI
import AnalyzersKit
import UIComponents

/// Settings → Agents → Capabilities: what the agent may do, as one toggle per
/// `AgentCapability`, plus the user's own extra instructions. The enabled set
/// serializes through `ConfigStore` as `AGENT_CAPABILITIES`; the agent's tool
/// registry refuses anything not in it — a toggle off is a refusal, not a hint.
struct CapabilitiesScreen: View {
    @Environment(ConfigStore.self) private var config
    /// Local mirror of the enabled set, mutated per toggle and persisted on
    /// every change (the same save-per-change the preference panes use).
    @State private var enabled: Set<String> = []
    @State private var prelude: String = ""
    @State private var loaded = false

    var body: some View {
        PaneScaffold(symbol: "checkmark.shield.fill", color: .mint, title: Names.Screen.capabilities,
                     caption: "What the agent may do. Every run is a tracked job, and the lists it cleans are always shown first.") {
            Section {
                ForEach(AgentCapability.all) { capability in
                    Toggle(isOn: binding(for: capability)) {
                        VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                            Text(capability.title)
                            Text(capability.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("What it may do")
            } footer: {
                Text(neverLine)
            }
            Section {
                TextEditor(text: $prelude)
                    .frame(minHeight: 72)
                    .onChange(of: prelude) { _, newValue in
                        guard loaded else { return }
                        config.agent.prelude = newValue
                        try? config.save()
                    }
            } header: {
                Text("Extra instructions")
            } footer: {
                Text("Always read before the agent answers. Your words stay on this Mac.")
            }
        }
        .onAppear {
            enabled = config.agent.capabilities
            prelude = config.agent.prelude
            loaded = true
        }
    }

    private func binding(for capability: AgentCapability) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(capability.id) },
            set: { isOn in
                guard loaded else { return }
                if isOn { enabled.insert(capability.id) } else { enabled.remove(capability.id) }
                config.agent.capabilities = enabled
                try? config.save()
            })
    }

    /// The one promise, in the footer where the toggles end: the invariants the
    /// agent inherits and cannot negotiate.
    private var neverLine: String {
        "The agent never deletes anything without showing the list first, never touches protected places, never kills on CPU, and never removes the protection around live AI sessions."
    }
}
