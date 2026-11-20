import SwiftUI
import AgentFeature
import AnalyzersKit
import UIComponents

/// The panel's one proactive agent line (S5): what a scheduled scan found that
/// is worth saying, with a button that opens Ask — where the proposal goes
/// through the same review as any typed question. The card proposes, never
/// applies; "don't suggest" for its category is in the context menu. Absent
/// when nothing is pending, so a quiet app's panel is unchanged.
struct MenuAskCard: View {
    /// Taken once per panel opening (`suggestionToShow` stamps the frequency
    /// cap, so it is never read from the body).
    @State private var suggestion: AskSuggestion?

    var body: some View {
        Group {
            if let suggestion {
                card(suggestion)
            }
        }
        .onAppear {
            suggestion = AskSuggestionCenter.shared.suggestionToShow()
        }
    }

    private func card(_ suggestion: AskSuggestion) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.mint)
                .accessibilityHidden(true)  // decorative — the line beside it says what was found
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.line).font(.callout)
                Text("Ask proposes this — nothing is cleaned without the list being shown first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Clean Up?") {
                AskSuggestionCenter.shared.dismiss()
                SettingsOpener.open(target: "ask")
            }
            .controlSize(.small)
            .help("Open Ask and review the list before anything happens")
        }
        .padding(8)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
        .contextMenu {
            Button("Don't Suggest \(suggestion.category.title) Again") {
                AskSuggestionCenter.shared.mute(category: suggestion.category)
                self.suggestion = nil
            }
        }
        .accessibilityElement(children: .contain)
    }
}
