import SwiftUI

/// The shell's one back/forward pair, leading the toolbar on every screen.
/// It walks the navigator's single history; screens never draw their own.
struct HistoryToolbar: ToolbarContent {
    let navigator: Navigator

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                navigator.back()
            } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .disabled(!navigator.canGoBack)
            .help("Back")

            Button {
                navigator.forward()
            } label: {
                Label("Forward", systemImage: "chevron.forward")
            }
            .disabled(!navigator.canGoForward)
            .help("Forward")
        }
    }
}
