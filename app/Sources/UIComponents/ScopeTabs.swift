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
/// and knows nothing about windows, so a window and the menu-bar panel use the same control. In
/// content (the menu-bar panel), small, remembered under a key the caller gives:
///
///     ScopeTabs(selection: $tab, items: [
///         ScopeTabItem(value: PanelTab.memory, title: Names.Group.memory, symbol: "memorychip"),
///         ScopeTabItem(value: PanelTab.storage, title: Names.Group.storage, symbol: "internaldrive"),
///     ])
///     .controlSize(.small)
///     .scopeTabMemory(key: "panel", selection: $tab, items: items)   // PanelTab: String raw value
///
/// A window puts it in a bar directly under its toolbar with `.scopeTabsToolbar(screen:items:selection:)`
/// (in SettingsFeature), which adds the View menu commands; the panel has neither. Never in a toolbar:
/// a toolbar moves a wide item into its `»` menu, and tabs must always be visible.
///
/// Every tab is a system `Toggle` in the button style: its on state stays a visibly stronger fill than
/// the others even in a window that is not in front (where an accent colour would not be drawn), and
/// the selected tab also has a filled symbol and a heavier title while the others are dimmer. When
/// the titles do not all fit the width it is given, the tabs give up their titles one at a time, the
/// last unselected one first (icon and count stay; the title is the tooltip and the accessibility
/// label), and the selected tab keeps its title, so every tab stays visible and clickable. That is
/// the one shape change, and it depends on width only, never on which tab is selected.
public struct ScopeTabs<Value: Hashable & Sendable>: View {
    @Binding var selection: Value
    let items: [ScopeTabItem<Value>]

    public init(selection: Binding<Value>, items: [ScopeTabItem<Value>]) {
        _selection = selection
        self.items = items
    }

    public var body: some View {
        assert((2...6).contains(items.count),
               "ScopeTabs takes two to six categories; a screen with one kind of thing has no tabs, and seven or more need a different control (ask the lead)")
        // ViewThatFits picks the first row that fits the width it is offered (its own measurement,
        // not a hand-made budget). The rows give up titles one tab at a time, the last unselected
        // tab first, so a title stays for as long as it fits; the last row (every unselected tab
        // as icon and count) is the one that always fits six tabs at 780. Six rows because a
        // screen has at most six tabs and at most five that are not selected.
        return ViewThatFits(in: .horizontal) {
            row(compressing: 0)
            row(compressing: 1)
            row(compressing: 2)
            row(compressing: 3)
            row(compressing: 4)
            row(compressing: 5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    /// The row with the last `compressing` unselected tabs reduced to icon and count.
    private func row(compressing: Int) -> some View {
        let unselected = items.filter { $0.value != selection }.map(\.value)
        let compressed = Set(unselected.suffix(compressing))
        return HStack(spacing: 6) {
            ForEach(items) { item in
                let selected = item.value == selection
                tab(item, selected: selected, showsTitle: !compressed.contains(item.value))
            }
        }
    }

    @ViewBuilder private func tab(_ item: ScopeTabItem<Value>, selected: Bool, showsTitle: Bool) -> some View {
        Toggle(isOn: Binding(get: { selected }, set: { if $0 { selection = item.value } })) {
            label(item, selected: selected, showsTitle: showsTitle)
        }
        .toggleStyle(.button)
        .buttonBorderShape(.capsule)
        // The selected tab must be unmistakable in a window that is not in front, where an accent
        // would not be drawn: the toggle's on fill, a filled symbol and a heavier title, with the
        // others dimmer.
        .symbolVariant(selected ? .fill : .none)
        .fontWeight(selected ? .semibold : .regular)
        .foregroundStyle(selected ? .primary : .secondary)
        .help(item.titleWithCount)
        .accessibilityLabel(item.titleWithCount)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func label(_ item: ScopeTabItem<Value>, selected: Bool, showsTitle: Bool) -> some View {
        // a count of zero is not shown: it says nothing and only makes the tab wider
        let count = item.count.flatMap { $0 > 0 ? $0 : nil }
        if showsTitle {
            Label {
                if let count {
                    // the selected tab keeps the primary colour for its count too, so its title reads as one
                    Text("\(item.title) \(Text("\(count)").foregroundStyle(selected ? .primary : .secondary))")
                } else {
                    Text(item.title)
                }
            } icon: { Image(systemName: item.symbol) }
            .labelStyle(.titleAndIcon)
        } else {
            HStack(spacing: 4) {
                Image(systemName: item.symbol)
                if let count { Text("\(count)").foregroundStyle(.secondary) }
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
