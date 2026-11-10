import SwiftUI

/// What a screen offers the menu bar. Menu items read this through
/// `focusedSceneValue` and are disabled — never hidden — when the focused
/// screen publishes nothing, so the toolbar and the menu share one action.
struct ScreenActions: Sendable {
    var refresh: (@MainActor @Sendable () -> Void)?
    var find: (@MainActor @Sendable () -> Void)?
}

extension FocusedValues {
    /// Published by the main window; the Go menu navigates through it.
    @Entry var navigator: Navigator?
    /// Published by a screen that can refresh or take focus into its search.
    @Entry var screenActions: ScreenActions?
}

extension View {
    /// A screen's hook into View › Refresh and View › Find. A screen that is
    /// covered by something pushed on top passes `isActive: false`, so the
    /// menu never acts on a table nobody can see.
    func screenActions(refresh: (@MainActor @Sendable () -> Void)? = nil,
                       find: (@MainActor @Sendable () -> Void)? = nil,
                       isActive: Bool = true) -> some View {
        focusedSceneValue(\.screenActions,
                          isActive ? ScreenActions(refresh: refresh, find: find) : nil)
    }
}
