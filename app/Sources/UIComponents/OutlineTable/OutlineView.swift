import AppKit

/// The `NSOutlineView` the table is built on. It adds only what AppKit's class
/// does not do: Return and Enter run the primary action, Space toggles ticks,
/// and the context menu follows the clicked-row rule.
@MainActor
final class OutlineNSView: NSOutlineView {
    /// Return and Enter. Returns whether it handled the key.
    var onPrimaryKey: (() -> Bool)?
    /// Space. Returns whether it handled the key.
    var onSpaceKey: (() -> Bool)?
    /// The menu for a right-click at this event; nil for none.
    var menuProvider: ((NSEvent) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        switch event.keyCode {
        case 36, 76:                                        // Return, keypad Enter
            if plain, onPrimaryKey?() == true { return }
        case 49:                                            // Space
            if plain, onSpaceKey?() == true { return }
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(event) ?? super.menu(for: event)
    }
}
