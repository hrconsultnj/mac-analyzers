import AppKit

/// The header's right-click menu: one item per hideable column, a checkmark on
/// each one that shows. The first column carries the hierarchy and is never
/// offered.
@MainActor
final class OutlineHeaderMenu: NSObject, NSMenuDelegate {
    private weak var outline: NSOutlineView?
    /// Column ids that may be hidden, with the title the menu shows.
    private var hideable: [(id: String, title: String)] = []
    let menu = NSMenu()

    init(outline: NSOutlineView) {
        self.outline = outline
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    func configure(hideable: [(id: String, title: String)]) {
        self.hideable = hideable
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let outline else { return }
        for entry in hideable {
            let item = NSMenuItem(title: entry.title, action: #selector(toggle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            let column = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(entry.id))
            item.state = (column?.isHidden ?? false) ? .off : .on
            menu.addItem(item)
        }
    }

    @objc private func toggle(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let outline,
              let column = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id)) else { return }
        column.isHidden.toggle()
    }
}
