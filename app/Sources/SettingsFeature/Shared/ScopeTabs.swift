import SwiftUI
import UIComponents

/// The window half of `ScopeTabs` (the plain view, `ScopeTabItem` and `ScopeTabMemory` are in
/// `UIComponents`, where the menu-bar panel can reach them): the tabs as ONE bar directly under the
/// window's toolbar, full width, remembered under `screen`, and as View menu commands (Command-1 to
/// Command-6) for the screen in front. A screen's call site (unchanged by where the bar sits):
///
///     DataScreen(title: "Caches & Builds", subtitle: "312 items · 23.4 GB") { ... }
///         .scopeTabsToolbar(screen: "caches", items: [
///             ScopeTabItem(value: Category.projects, title: Names.Category.projects, symbol: "folder", count: 12),
///             ...
///         ], selection: $category)       // Category: String raw value, Hashable, Sendable
///
/// The bar is a `safeAreaBar` at the top edge, so the system draws it with the toolbar's material and
/// scroll-edge effect and a list or table scrolls under it. It is not in the toolbar on purpose: a
/// toolbar item that does not fit goes into `»`, and no toolbar API can keep a group of tabs out of
/// it (measured at 900 and 1100 on screens with their own buttons). That leaves the toolbar to the
/// screen's actions and search. Fewer than two items draws no bar at all.
///
/// A deep link to a category is `<screen>:<category raw value>`: the screen's group resolves it by
/// calling `ScopeTabMemory.select(_:in:)` before navigating (a link only navigates and selects).
/// `isActive: false` while something is pushed over the screen: its tabs are hidden then, so the
/// View menu must not act on them.
// The types live in UIComponents (the menu-bar panel imports that module). These module-internal
// names let a screen USE them in expressions without importing it (a call to `scopeTabsToolbar`
// with `ScopeTabItem(...)` items). A file that declares a STORED PROPERTY of these types must
// still `import UIComponents`: the compiler warns otherwise, and `scripts/check.sh app` fails on it.
typealias ScopeTabItem<Value: Hashable & Sendable> = UIComponents.ScopeTabItem<Value>
typealias ScopeTabs<Value: Hashable & Sendable> = UIComponents.ScopeTabs<Value>
typealias ScopeTabMemory = UIComponents.ScopeTabMemory

extension View {
    func scopeTabsToolbar<Value: Hashable & Sendable & RawRepresentable>(
        screen: String, items: [ScopeTabItem<Value>], selection: Binding<Value>, isActive: Bool = true
    ) -> some View where Value.RawValue == String {
        modifier(ScopeTabsToolbarModifier(screen: screen, items: items, selection: selection, isActive: isActive))
    }
}

private struct ScopeTabsToolbarModifier<Value: Hashable & Sendable & RawRepresentable>: ViewModifier
where Value.RawValue == String {
    let screen: String
    let items: [ScopeTabItem<Value>]
    @Binding var selection: Value
    let isActive: Bool
    @Environment(Navigator.self) private var navigator
    @Environment(\.stackDepth) private var depth

    func body(content: Content) -> some View {
        // Top of the stack by construction: a screen with something pushed over it publishes no
        // commands, so no screen can forget `isActive`.
        let isActive = isActive && navigator.path.count == depth && items.count >= 2
        return content
            .safeAreaBar(edge: .top, spacing: 0) {
                if items.count >= 2 {
                    ScopeTabs(selection: $selection, items: items)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scenePadding(.horizontal)
                        .padding(.vertical, 8)
                }
            }
            .focusedSceneValue(\.scopeTabs, isActive ? ScopeTabsCommands(
                titles: items.map(\.title),
                select: { index in if items.indices.contains(index) { selection = items[index].value } }) : nil)
            .scopeTabMemory(key: screen, selection: $selection, items: items)
    }
}

extension EnvironmentValues {
    /// How many screens are below this one in its section's stack: 0 for the section's own screen.
    @Entry var stackDepth = 0
}

/// What the View menu reads: the focused screen's tab titles and how to choose one.
struct ScopeTabsCommands: Sendable {
    let titles: [String]
    let select: @MainActor @Sendable (Int) -> Void
}

extension FocusedValues {
    @Entry var scopeTabs: ScopeTabsCommands?
}
