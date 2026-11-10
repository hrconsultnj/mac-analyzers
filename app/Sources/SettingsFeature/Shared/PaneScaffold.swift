import SwiftUI
import UIComponents

/// The ONE container every settings pane uses: centered header as the first
/// row of the grouped form, pane name as the window title.
///
/// LESSON (v2.7.1 regression): the header must stay INSIDE the Form. Hoisting
/// it above the Form put it in the toolbar's backdrop region — rendered as a
/// light band with a doubled title. And no .scrollEdgeEffectStyle here: the
/// hard edge paints an opaque backdrop that fights the Settings window.
struct PaneScaffold<Content: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let caption: String
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer(minLength: 0)
                    PaneHeader(symbol: symbol, color: color, title: title, caption: caption)
                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            content
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}
