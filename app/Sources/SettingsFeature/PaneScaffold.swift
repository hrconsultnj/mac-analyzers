import SwiftUI
import UIComponents

/// The ONE container every settings pane uses: a plain (un-boxed,
/// System-Settings-style) header that scrolls with the grouped form beneath
/// it, plus the pane name as the window title. Identical top anatomy for
/// every pane — switching panes never shifts the layout.
struct PaneScaffold<Content: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let caption: String
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                PaneHeader(symbol: symbol, color: color, title: title, caption: caption)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            content
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}
