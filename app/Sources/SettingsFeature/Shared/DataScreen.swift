import SwiftUI

/// The frame of a screen that shows data: the title and a one-line subtitle in
/// the window's toolbar, then the content filling every pixel left. There is no
/// banner header above the data and no centred column — `PaneScaffold` and its
/// header are for settings forms only. The content brings its own insets (a
/// `List`, a `Table` and a `Form` all have the system's); anything else asks for
/// the standard margin with `padded`.
///
///     DataScreen(title: "Login Items", subtitle: "12 items") {
///         Table(items) { … }
///     }
///     .searchable(text: $query)
///     .toolbar { … }
///
/// Search, toolbar items and the inspector attach to the screen as usual; they
/// belong to the window, so they go on the `DataScreen`, not inside it.
///
/// Placement: content that fills (a `List`, a `Table`) is unaffected. Content smaller than the
/// screen is centred, and `padded: true` is for plain content with no insets of its own and puts it
/// at the top left. An empty, failed or loading state is NOT placed by the screen at all: it is
/// `EmptyState` or `LoadingState` (`Shared/ScreenState.swift`), which fill whatever space is left
/// (under a banner, a facts strip, a tab bar) and centre themselves there, so a state never lands at
/// the top left; `scripts/check.sh states` refuses a bare `ContentUnavailableView` or screen-state
/// `ProgressView` anywhere else.
struct DataScreen<Content: View>: View {
    let title: String
    var subtitle: String?
    /// Adds the standard window margin, for content that has none of its own.
    var padded = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padded ? .all : [])
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: padded ? .topLeading : .center)
            .navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
    }
}
