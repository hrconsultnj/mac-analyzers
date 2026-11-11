import SwiftUI
import UIComponents

/// The window half of `ScopeTabs` (the plain view, `ScopeTabItem` and `ScopeTabMemory` are in
/// `UIComponents`, where the menu-bar panel can reach them): the tabs in the toolbar with the
/// highest priority, remembered under `screen`, and as View menu commands (Command-1 to
/// Command-6) for the screen in front. A screen's call site:
///
///     DataScreen(title: "Caches & Builds", subtitle: "312 items · 23.4 GB") { ... }
///         .scopeTabsToolbar(screen: "caches", items: [
///             ScopeTabItem(value: Category.projects, title: Names.Category.projects, symbol: "folder", count: 12),
///             ...
///         ], selection: $category)       // Category: String raw value, Hashable, Sendable
///
/// A deep link to a category is `<screen>:<category raw value>`: the screen's group resolves it by
/// calling `ScopeTabMemory.select(_:in:)` before navigating (a link only navigates and selects).
/// `isActive: false` while something is pushed over the screen: its tabs are hidden then, so the
/// View menu must not act on them. On a Mac before macOS 26.1 there is no visibility priority:
/// the system's own overflow order applies (see `toolbarRank`).
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

    func body(content: Content) -> some View {
        content
            .toolbar { ScopeTabsToolbar(items: items, selection: $selection) }
            .focusedSceneValue(\.scopeTabs, isActive ? ScopeTabsCommands(
                titles: items.map(\.title),
                select: { index in if items.indices.contains(index) { selection = items[index].value } }) : nil)
            .scopeTabMemory(key: screen, selection: $selection, items: items)
    }
}

/// The tabs as their own toolbar item: a spacer after it keeps whatever the screen adds
/// (an action such as Audit) out of the same glass capsule at every width.
private struct ScopeTabsToolbar<Value: Hashable & Sendable>: ToolbarContent {
    let items: [ScopeTabItem<Value>]
    @Binding var selection: Value

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) { ScopeTabs(selection: $selection, items: items) }
            .toolbarRank(.primary)
        ToolbarSpacer(.fixed, placement: .principal)
    }
}

/// What the View menu reads: the focused screen's tab titles and how to choose one.
struct ScopeTabsCommands: Sendable {
    let titles: [String]
    let select: @MainActor @Sendable (Int) -> Void
}

extension FocusedValues {
    @Entry var scopeTabs: ScopeTabsCommands?
}
