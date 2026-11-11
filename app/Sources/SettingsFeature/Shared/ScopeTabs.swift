import SwiftUI

/// One category of a screen: what it is called, its symbol, how many are in it.
struct ScopeTabItem<Value: Hashable & Sendable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String
    /// Shown as plain text after the title; nil for a tab with no meaningful count ("All").
    var count: Int?

    var id: Value { value }
}

/// Level 2 of the app's one way from many things to one: a screen's categories, as
/// buttons that each show an icon AND a title and, where it means something, how many
/// are in it. No other tab control exists. Two to six categories (a seventh is a debug
/// assertion: the guideline's answer is a different control, decided once for the app);
/// never a second row of tabs under these.
///
/// The control is a plain view: it takes its size from the environment's `controlSize`,
/// sets no widths, and knows nothing about toolbars. In content (the menu-bar panel):
///
///     ScopeTabs(selection: $tab, items: items)
///         .controlSize(.small)
///         .scopeTabMemory(key: "panel", selection: $tab, items: items)   // remembered under that key
///
/// In a window, the toolbar modifier puts it in the toolbar with the highest visibility
/// priority, remembers the choice and adds the View menu commands (Command-1 to
/// Command-6):
///
///     DataScreen(title: "Caches & Builds", subtitle: "312 items · 23.4 GB") { ... }
///         .scopeTabsToolbar(screen: "caches", items: [
///             ScopeTabItem(value: Category.projects, title: Names.Category.projects, symbol: "folder", count: 12),
///             ...
///         ], selection: $category)       // Category: String raw value, Hashable, Sendable
///
/// Drawn as `Toggle(.button)` with a `Label`: the only native arrangement that shows both
/// icon and title (a segmented `Picker` keeps the icon, a palette `Picker` the title;
/// `TabView` draws neither). That departs from Apple's "text or images, not both" for
/// segmented controls, on purpose. The drawing is `ScopeTabButtons`, one private view in
/// this file; a different native control would replace only that.
///
/// A deep link to a category is `<screen>:<category raw value>`: the screen's group
/// resolves it by calling `ScopeTabMemory.select(_:in:)` before navigating (a link only
/// navigates and selects), and the screen reads its remembered tab when it appears. On a
/// Mac before macOS 26.1 there is no visibility priority: the system's own overflow
/// order applies (`visibilityPriority` is wrapped in `#available` here, once).
struct ScopeTabs<Value: Hashable & Sendable>: View {
    @Binding var selection: Value
    let items: [ScopeTabItem<Value>]

    var body: some View {
        assert((2...6).contains(items.count),
               "ScopeTabs takes two to six categories; a screen with one kind of thing has no tabs, and seven or more need a different control (ask the lead)")
        return ScopeTabButtons(selection: $selection, items: items)
    }
}

/// The drawing of the tabs, and only that.
private struct ScopeTabButtons<Value: Hashable & Sendable>: View {
    @Binding var selection: Value
    let items: [ScopeTabItem<Value>]

    var body: some View {
        ControlGroup {
            ForEach(items) { item in
                Toggle(isOn: Binding(get: { selection == item.value }, set: { if $0 { selection = item.value } })) {
                    Label { title(item) } icon: { Image(systemName: item.symbol) }
                }
                .toggleStyle(.button)
            }
        }
        .labelStyle(.titleAndIcon)
        .help("Choose a category")
    }

    private func title(_ item: ScopeTabItem<Value>) -> Text {
        guard let count = item.count else { return Text(item.title) }
        return Text("\(item.title) \(Text("\(count)").foregroundStyle(.secondary))")
    }
}

extension View {
    /// Remembers the selected tab under `key`, across window close and relaunch, and
    /// restores it when the view appears if the remembered tab still exists.
    func scopeTabMemory<Value: Hashable & Sendable & RawRepresentable>(
        key: String, selection: Binding<Value>, items: [ScopeTabItem<Value>]
    ) -> some View where Value.RawValue == String {
        modifier(ScopeTabMemoryModifier(key: key, items: items, selection: selection))
    }

    /// A window's tabs: in the toolbar (own group, highest priority), remembered under
    /// `screen`, and as View menu commands for the screen in front.
    func scopeTabsToolbar<Value: Hashable & Sendable & RawRepresentable>(
        screen: String, items: [ScopeTabItem<Value>], selection: Binding<Value>
    ) -> some View where Value.RawValue == String {
        modifier(ScopeTabsToolbarModifier(screen: screen, items: items, selection: selection))
    }
}

private struct ScopeTabMemoryModifier<Value: Hashable & Sendable & RawRepresentable>: ViewModifier
where Value.RawValue == String {
    let key: String
    let items: [ScopeTabItem<Value>]
    @Binding var selection: Value

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let saved = ScopeTabMemory.read(key), let value = Value(rawValue: saved),
                   items.contains(where: { $0.value == value }) {
                    selection = value
                }
            }
            .onChange(of: selection) { _, value in ScopeTabMemory.write(key, value.rawValue) }
    }
}

private struct ScopeTabsToolbarModifier<Value: Hashable & Sendable & RawRepresentable>: ViewModifier
where Value.RawValue == String {
    let screen: String
    let items: [ScopeTabItem<Value>]
    @Binding var selection: Value

    func body(content: Content) -> some View {
        content
            .toolbar { ScopeTabsToolbar(items: items, selection: $selection) }
            .focusedSceneValue(\.scopeTabs, ScopeTabsCommands(
                titles: items.map(\.title),
                select: { index in if items.indices.contains(index) { selection = items[index].value } }))
            .scopeTabMemory(key: screen, selection: $selection, items: items)
    }
}

/// The tabs as their own toolbar item: a spacer after it keeps whatever the screen adds
/// (an action such as Audit) out of the same glass capsule at every width.
private struct ScopeTabsToolbar<Value: Hashable & Sendable>: ToolbarContent {
    let items: [ScopeTabItem<Value>]
    @Binding var selection: Value

    var body: some ToolbarContent {
        if #available(macOS 26.1, *) {
            ToolbarItem(placement: .principal) { ScopeTabs(selection: $selection, items: items) }
                .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .principal) { ScopeTabs(selection: $selection, items: items) }
        }
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

/// The selected tab of each screen (or panel), kept in the user defaults so it survives
/// the window closing and the app relaunching (a scene-scoped store is lost when the
/// window closes on macOS; the navigator's own restore uses the defaults too).
enum ScopeTabMemory {
    private static func key(_ screen: String) -> String { "scopeTab.\(screen)" }
    static func read(_ screen: String) -> String? { UserDefaults.standard.string(forKey: key(screen)) }
    static func write(_ screen: String, _ raw: String) { UserDefaults.standard.set(raw, forKey: key(screen)) }
    /// A deep link to a category: remembers it, and the screen picks it up when it appears.
    static func select(_ raw: String, in screen: String) { write(screen, raw) }
}
