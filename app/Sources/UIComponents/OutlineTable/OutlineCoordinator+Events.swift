import AppKit
import SwiftUI

/// What the person does in the outline becomes the pending overlay, and reaches
/// the caller's bindings on the next main turn, in one coalesced flush.
extension OutlineCoordinator {

    // MARK: - effective values: the caller's, merged with what is pending

    var effectiveExpanded: Set<Row.ID> {
        configuration.expanded.wrappedValue.union(pending.opened).subtracting(pending.closed)
    }

    var effectiveSelection: Set<Row.ID> {
        pending.selection ?? configuration.selection.get()
    }

    var effectiveSortOrder: [KeyPathComparator<Row>] {
        pending.sortOrder ?? configuration.sortOrder?.wrappedValue ?? []
    }

    func selectedIDs() -> Set<Row.ID> {
        var ids = Set<Row.ID>()
        for row in outline.selectedRowIndexes {
            if let node = outline.item(atRow: row) as? Node, node.header == nil { ids.insert(node.id) }
        }
        return ids
    }

    // MARK: - AppKit tells us

    func selectionDidChange() {
        guard !isApplying else { return }
        let ids = selectedIDs()
        knownSelection = ids
        pending.selection = ids
        scheduleFlush()
    }

    func expansionDidChange(_ notification: Notification, opened: Bool) {
        guard !isApplying, let node = notification.userInfo?["NSObject"] as? Node else { return }
        if opened {
            pending.opened.insert(node.id)
            pending.closed.remove(node.id)
        } else {
            pending.closed.insert(node.id)
            pending.opened.remove(node.id)
        }
        scheduleFlush()
    }

    func sortDescriptorsDidChange() {
        guard !isApplying else { return }
        pending.sortOrder = OutlineSortMapping.comparators(from: outline.sortDescriptors, columns: configuration.columns)
        scheduleFlush()
    }

    // MARK: - primary action, keys, ticks

    /// The rows an action acts on: the clicked row alone when it is outside the
    /// selection, otherwise the whole selection (AppKit's rule).
    private func idsForAction(clickedRow: Int) -> Set<Row.ID> {
        let selection = selectedIDs()
        guard clickedRow >= 0, let node = outline.item(atRow: clickedRow) as? Node, node.header == nil else { return selection }
        return outline.selectedRowIndexes.contains(clickedRow) ? selection : [node.id]
    }

    func handleDoubleClick() {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? Node else { return }
        if let action = configuration.primaryAction, node.header == nil {
            action(idsForAction(clickedRow: row))
        } else if node.isExpandable {
            // without a primary action a double-click opens or closes the group
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        }
    }

    func primaryKey() -> Bool {
        guard let action = configuration.primaryAction else { return false }
        let ids = selectedIDs()
        guard !ids.isEmpty else { return false }
        action(ids)
        return true
    }

    func handleTick(_ sender: NSButton) {
        let row = outline.row(for: sender)
        guard row >= 0, let node = outline.item(atRow: row) as? Node, let state = effectiveTick(for: node) else { return }
        guard let value = state.valueAfterClick else {
            // a tick that cannot be chosen does nothing; draw it as it was
            sender.state = .off
            return
        }
        sender.state = value ? .on : .off
        recordTick(node, value)
        scheduleFlush()
    }

    /// Space: ticks every selected row that can be chosen — all on unless they
    /// all are already, then all off.
    func spaceKey() -> Bool {
        guard configuration.ticks != nil else { return false }
        let targets = selectedIDs().compactMap { nodes.node(for: $0) }.filter { effectiveTick(for: $0)?.isAvailable == true }
        guard !targets.isEmpty else { return true }
        let allOn = targets.allSatisfy { effectiveTick(for: $0) == .on }
        for node in targets { recordTick(node, !allOn) }
        scheduleFlush()
        // the checkboxes show it now, not after the caller has heard
        let first = IndexSet(integer: 0)
        for node in targets {
            let row = outline.row(forItem: node)
            if row >= 0 { outline.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: first) }
        }
        return true
    }

    private func recordTick(_ node: Node, _ value: Bool) {
        pending.tickValues[node.id] = value
        pending.tickWrites.append((node.id, value))
    }

    // MARK: - context menu

    func contextMenu(for event: NSEvent) -> NSMenu? {
        guard let build = configuration.menu else { return nil }
        let row = outline.row(at: outline.convert(event.locationInWindow, from: nil))
        if row >= 0, let node = outline.item(atRow: row) as? Node, node.header != nil { return nil }
        let ids = idsForAction(clickedRow: row)
        return NSHostingMenu(rootView: OutlineMenuRoot(content: build(ids), environment: environment))
    }

    // MARK: - rule 2: the flush

    func scheduleFlush() {
        guard !flushIsQueued else { return }
        flushIsQueued = true
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { flush() }
        }
    }

    /// Delivers what the person did to the caller's bindings: one write each,
    /// after the overlay is cleared, so the update that follows finds nothing
    /// to change (no echo loop).
    private func flush() {
        flushIsQueued = false
        let delivered = pending
        pending = OutlinePending()
        if !delivered.opened.isEmpty || !delivered.closed.isEmpty {
            let current = configuration.expanded.wrappedValue
            let next = current.union(delivered.opened).subtracting(delivered.closed)
            if next != current { configuration.expanded.wrappedValue = next }
        }
        if let selection = delivered.selection, selection != configuration.selection.get() {
            configuration.selection.set(selection)
        }
        if let sortOrder = delivered.sortOrder, let binding = configuration.sortOrder {
            binding.wrappedValue = sortOrder
        }
        for write in delivered.tickWrites {
            if let node = nodes.node(for: write.id), let ticks = configuration.ticks, ticks.state(node.row).isAvailable {
                ticks.set(node.row, write.value)
            }
        }
        // a tick on a member changes its group's box (on, mixed, off); a screen whose body
        // does not read the tick state is not updated, so the visible rows are redrawn here
        if !delivered.tickWrites.isEmpty, !isApplying, depth == 0 { updater.refreshVisibleValues() }
    }
}
