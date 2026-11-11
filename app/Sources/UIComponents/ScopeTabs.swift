import SwiftUI

/// One category of a screen: what it is called, its symbol, how many are in it.
public struct ScopeTabItem<Value: Hashable & Sendable>: Identifiable {
    public let value: Value
    public let title: String
    public let symbol: String
    /// Shown as plain text after the title; nil for a tab with no meaningful count ("All").
    public var count: Int?

    public var id: Value { value }

    /// "Running 2", or just "Running" when there is nothing to count: a tab with a count of zero says nothing.
    var titleWithCount: String {
        guard let count, count > 0 else { return title }
        return "\(title) \(count)"
    }

    public init(value: Value, title: String, symbol: String, count: Int? = nil) {
        self.value = value
        self.title = title
        self.symbol = symbol
        self.count = count
    }
}

/// Level 2 of the app's one way from many things to one: a screen's categories, as buttons that
/// each show an icon AND a title and, where it means something, how many are in it. No other tab
/// control exists. Two to six categories (a seventh is a debug assertion: the guideline's answer is
/// a different control, decided once for the app); never a second row of tabs under these.
///
/// This is the plain view: it takes its size from the environment's `controlSize`, sets no widths
/// and knows nothing about toolbars, so a window and the menu-bar panel use the same control. In
/// content (the menu-bar panel), small, remembered under a key the caller gives:
///
///     ScopeTabs(selection: $tab, items: [
///         ScopeTabItem(value: PanelTab.memory, title: Names.Group.memory, symbol: "memorychip"),
///         ScopeTabItem(value: PanelTab.storage, title: Names.Group.storage, symbol: "internaldrive"),
///     ])
///     .controlSize(.small)
///     .scopeTabMemory(key: "panel", selection: $tab, items: items)   // PanelTab: String raw value
///
/// A window puts it in the toolbar with `.scopeTabsToolbar(screen:items:selection:)` (in
/// SettingsFeature), which adds the toolbar's priority and the View menu commands; the panel has
/// neither. Drawn as `Toggle(.button)` with a `Label`: the only native arrangement that shows both
/// icon and title (a segmented `Picker` keeps the icon, a palette `Picker` the title; `TabView`
/// draws neither). That departs from Apple's "text or images, not both" for segmented controls, on
/// purpose. The drawing is `ScopeTabButtons`, one private view; a different native control would
/// replace only that.
public struct ScopeTabs<Value: Hashable & Sendable>: View {
    /// How the categories are drawn: every one as a button, or collapsed into ONE control that
    /// shows the current category (icon, title, count) and opens a menu of all of them. Same
    /// component, same state; a window's toolbar switches to `.menu` when the buttons cannot fit.
    public enum Style: Sendable { case tabs, menu, measure }

    @Binding var selection: Value
    let items: [ScopeTabItem<Value>]
    let style: Style

    public init(selection: Binding<Value>, items: [ScopeTabItem<Value>], style: Style = .tabs) {
        _selection = selection
        self.items = items
        self.style = style
    }

    public var body: some View {
        assert((2...6).contains(items.count),
               "ScopeTabs takes two to six categories; a screen with one kind of thing has no tabs, and seven or more need a different control (ask the lead)")
        return Group {
            switch style {
            case .tabs: ScopeTabButtons(selection: $selection, items: items)
            case .menu: ToolbarChoice(selection: $selection, items: items)
            case .measure: ScopeTabButtons(selection: $selection, items: items, rowForMeasuring: true)
            }
        }
    }
}

/// A choice that lives in a toolbar as ONE menu button showing the current choice (icon, title,
/// count) and listing every choice with its icon: the collapsed form of `ScopeTabs`, the way Finder's
/// view switcher collapses, and the way to put any other picker in a toolbar (a bare `Picker` there
/// renders as an empty capsule). No limit on how many choices.
///
///     ToolbarChoice(selection: $range, items: ranges)     // ScopeTabItem(value:title:symbol:)
public struct ToolbarChoice<Value: Hashable & Sendable>: View {
    public init(selection: Binding<Value>, items: [ScopeTabItem<Value>]) {
        _selection = selection
        self.items = items
    }

    @Binding var selection: Value
    let items: [ScopeTabItem<Value>]

    public var body: some View {
        let current = items.first { $0.value == selection } ?? items[0]
        Menu {
            Picker("Category", selection: $selection) {
                ForEach(items) { item in
                    Label { Text(item.titleWithCount) } icon: { Image(systemName: item.symbol) }.tag(item.value)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label { Text(current.titleWithCount) } icon: { Image(systemName: current.symbol) }
        }
        .menuIndicator(.visible)
        .labelStyle(.titleAndIcon)
        .help("Choose a category")
    }
}

/// The drawing of the tabs, and only that.
private struct ScopeTabButtons<Value: Hashable & Sendable>: View {
    @Binding var selection: Value
    let items: [ScopeTabItem<Value>]
    /// Draws the same buttons side by side in a plain row, for a hidden copy that reports their width
    /// (a `ControlGroup` outside a toolbar does not lay out as one row).
    var rowForMeasuring = false

    var body: some View {
        if rowForMeasuring {
            HStack(spacing: 0) { buttons }.labelStyle(.titleAndIcon)
        } else {
            ControlGroup { buttons }
                .labelStyle(.titleAndIcon)
                .help("Choose a category")
        }
    }

    private var buttons: some View {
        ForEach(items) { item in
            Toggle(isOn: Binding(get: { selection == item.value }, set: { if $0 { selection = item.value } })) {
                Label { title(item) } icon: { Image(systemName: item.symbol) }
            }
            .toggleStyle(.button)
        }
    }

    private func title(_ item: ScopeTabItem<Value>) -> Text {
        // a count of zero is not shown: it only makes the tabs wider
        guard let count = item.count, count > 0 else { return Text(item.title) }
        return Text("\(item.title) \(Text("\(count)").foregroundStyle(.secondary))")
    }
}

public extension View {
    /// Remembers the selected tab under `key`, across window close and relaunch, restores it when
    /// the view appears if the remembered tab still exists, and follows `ScopeTabMemory.select`
    /// for the same key (a deep link to a category of a screen that is already showing).
    func scopeTabMemory<Value: Hashable & Sendable & RawRepresentable>(
        key: String, selection: Binding<Value>, items: [ScopeTabItem<Value>]
    ) -> some View where Value.RawValue == String {
        modifier(ScopeTabMemoryModifier(key: key, items: items, selection: selection))
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
            .onReceive(NotificationCenter.default.publisher(for: ScopeTabMemory.selected)) { note in
                guard note.userInfo?["screen"] as? String == key, let raw = note.userInfo?["raw"] as? String,
                      let value = Value(rawValue: raw), items.contains(where: { $0.value == value }) else { return }
                selection = value
            }
    }
}

/// The selected tab of each screen (or panel), kept in the user defaults so it survives the
/// window closing and the app relaunching (a scene-scoped store is lost when the window closes on
/// macOS; the navigator's own restore uses the defaults too).
public enum ScopeTabMemory {
    private static func key(_ screen: String) -> String { "scopeTab.\(screen)" }
    static func read(_ screen: String) -> String? { UserDefaults.standard.string(forKey: key(screen)) }
    static func write(_ screen: String, _ raw: String) { UserDefaults.standard.set(raw, forKey: key(screen)) }
    /// A deep link to a category: a screen already showing it switches at once (it observes
    /// `selected`); one that is not reads the memory when it appears.
    public static func select(_ raw: String, in screen: String) {
        write(screen, raw)
        NotificationCenter.default.post(name: selected, object: nil, userInfo: ["screen": screen, "raw": raw])
    }
    public static let selected = Notification.Name("scopeTabMemory.selected")
}
