import SwiftUI

// STOPGAP. The shared `ScopeTabs` (UIComponents, from the foundation track)
// replaces this file; the call site is shaped like it (a binding, the
// categories, and for each a name, a symbol and a count) so the swap is one
// line per screen, and this file is deleted then.
//
// A choice between a few categories, drawn as toggle buttons that each show an
// icon AND a title (and how many). A segmented `Picker` cannot do that on macOS
// (it draws the title or the icon, never both: rendered), and Toggle with the
// button style is the system's own control for it, mutually exclusive through
// the one binding.
struct ScopeButtons<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let symbol: (Item) -> String
    let count: (Item) -> Int?

    var body: some View {
        HStack {
            ForEach(items) { item in
                Toggle(isOn: Binding(get: { selection == item },
                                     set: { if $0 { selection = item } })) {
                    Label(text(for: item), systemImage: symbol(item))
                }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
            }
        }
    }

    private func text(for item: Item) -> String {
        count(item).map { "\(title(item)) \($0)" } ?? title(item)
    }
}
