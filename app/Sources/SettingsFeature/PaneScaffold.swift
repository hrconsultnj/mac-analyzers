import SwiftUI
import UIComponents

/// The ONE container every settings pane uses: a hard-centered,
/// System-Settings-style header PINNED above the grouped form (outside the
/// Form entirely — macOS draws a section card around any Form row, clear
/// background or not, which is why the header used to look boxed), plus the
/// pane name as the window title. Identical anatomy for every pane.
struct PaneScaffold<Content: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let caption: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                PaneHeader(symbol: symbol, color: color, title: title, caption: caption)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            Form {
                content
            }
            .formStyle(.grouped)
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
        .navigationTitle(title)
    }
}
