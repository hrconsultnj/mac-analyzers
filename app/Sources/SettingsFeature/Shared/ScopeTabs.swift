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
    @State private var columnWidth: CGFloat = 0
    @State private var fullWidth: CGFloat = 0
    @State private var menuWidth: CGFloat = 0
    @State private var titleWidth: CGFloat = ToolbarBudget.defaultTitleWidth

    /// What the toolbar holds besides the tabs: nav buttons, search, the title block.
    private var base: CGFloat { ToolbarBudget.chrome + titleWidth }

    /// The full row of tabs does not fit beside the nav buttons and the title: collapse them into
    /// one control that shows the current tab, rather than let the system drop them into `»`.
    private var collapsed: Bool { columnWidth > 0 && fullWidth > 0 && columnWidth < base + fullWidth }

    /// The job status item gives way before the tabs do: it shows only when it fits beside whichever
    /// form of the tabs is on screen.
    private var allowsStatus: Bool {
        guard columnWidth > 0, fullWidth > 0 else { return true }
        return columnWidth >= base + (collapsed ? menuWidth : fullWidth) + ToolbarBudget.statusItem
    }

    func body(content: Content) -> some View {
        // Top of the stack by construction: a screen with something pushed over it publishes no
        // commands, so no screen can forget `isActive`.
        let isActive = isActive && navigator.path.count == depth
        return content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { columnWidth = $0 }
            // the full row's own width, measured where it can be laid out freely
            .background {
                ScopeTabs(selection: $selection, items: items, style: .measure)
                    .fixedSize().hidden().accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { fullWidth = $0 }
            }
            .background {
                ScopeTabs(selection: $selection, items: items, style: .menu)
                    .fixedSize().hidden().accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { menuWidth = $0 }
            }
            .preference(key: ToolbarAllowsStatusKey.self, value: allowsStatus)
            .onPreferenceChange(ToolbarTitleWidthKey.self) { titleWidth = $0 ?? ToolbarBudget.defaultTitleWidth }
            .toolbar { ScopeTabsToolbar(items: items, selection: $selection, collapsed: collapsed) }
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
    let collapsed: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ScopeTabs(selection: $selection, items: items, style: collapsed ? .menu : .tabs)
        }
        .toolbarRank(.primary)
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
