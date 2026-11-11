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
struct DataScreen<Content: View>: View {
    let title: String
    var subtitle: String?
    /// Adds the standard window margin, for content that has none of its own.
    var padded = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padded ? .all : [])
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
            .preference(key: ToolbarTitleWidthKey.self, value: ToolbarBudget.titleWidth(title: title, subtitle: subtitle))
    }
}
