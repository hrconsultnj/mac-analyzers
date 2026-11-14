import SwiftUI

/// The one way a screen shows that it has nothing to show, is still reading, or could not read: the system's
/// `ContentUnavailableView` for an empty or failed state and a `ProgressView` for a loading one, each filling
/// whatever space the screen has left and centring itself in it. The two are wrapped here, once, because a bare
/// `ContentUnavailableView` or `ProgressView` takes only its own size: under a banner, a facts strip or any other
/// content in a stack it lands at the top left, and on a screen of its own it sits wherever the screen's frame puts
/// small content. No screen places its own state: it says WHAT the state is (icon, title, description, and the
/// button that fixes it where that action exists on the screen) and this says WHERE (`scripts/check.sh states`
/// refuses a bare one anywhere else).
///
///     EmptyState("Nothing Has Run Yet", systemImage: "list.bullet.rectangle", description: Text("…"))
///     EmptyState { Label("No Preview Yet", systemImage: "eye") } description: { Text("…") } actions: { Button("Preview") { … } }
///     EmptyState.search(text: query)
///     LoadingState("Reading the logs…")
struct EmptyState<Label: View, Description: View, Actions: View>: View {
    private let content: ContentUnavailableView<Label, Description, Actions>

    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() },
         @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        content = ContentUnavailableView(label: label, description: description, actions: actions)
    }

    var body: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    /// A title, a symbol and one sentence: the common empty state.
    init(_ title: String, systemImage: String, description: Text? = nil) {
        content = ContentUnavailableView(title, systemImage: systemImage, description: description)
    }
}

extension EmptyState where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    /// "No results for …": the system's own search state.
    static func search(text: String) -> some View {
        ContentUnavailableView.search(text: text).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A screen that is still reading or working: a spinner, with what it is doing under it when it has something to say
/// (`title`, and a sentence of `detail`) and a button after that when the work can be stopped, centred in the space the
/// screen has.
struct LoadingState<Actions: View>: View {
    private let title: String?
    private let detail: String?
    private let actions: Actions

    init(_ title: String? = nil, detail: String? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        VStack {
            ProgressView()
            if let title { Text(title).foregroundStyle(.secondary) }
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
