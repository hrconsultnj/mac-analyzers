import SwiftUI
import AnalyzersKit

/// Ask: the agent's home — a health summary written from the latest reports,
/// the template grid, the chat input, and the trust line.
///
/// PHASE 1 SCAFFOLD: the templates, session state and conversation screens
/// are Phase 4 (lane C), which replaces this screen wholesale. The trust line
/// below is the feature's one promise and stays true at every phase.
struct AskHomeView: View {
    var body: some View {
        PaneScaffold(symbol: "text.bubble", color: .mint, title: Names.Screen.ask,
                     caption: "Ask about this Mac in your own words.") {
            Section {
                Text("Runs on this Mac, nothing leaves, and nothing is deleted without the list being shown first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The templates and conversation arrive with the agent update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Ask")
            }
        }
    }
}
