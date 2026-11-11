import AppKit

/// Applies the caller's rows to AppKit. It is the only code that changes what
/// the outline holds, and it runs only when AppKit is not calling in (the
/// coordinator checks that before calling `apply`).
///
/// The order, per update:
/// 1. note where the person is looking (scroll anchor);
/// 2. stage the next node tree beside the one AppKit has;
/// 3. plan a diff per level, walking the root and every open parent;
/// 4. inside one begin/endUpdates: removals, then moves, then inserts, with the
///    node tree changed in step with each call;
/// 5. reload what the update could not reach (closed parents whose children
///    changed, rows whose triangle appeared or went), then sync expansion,
///    refresh the visible values, sync selection and sort, and restore the scroll.
@MainActor
final class OutlineUpdater<Row: Identifiable> {
    typealias Node = OutlineNode<Row>

    private unowned let coordinator: OutlineCoordinator<Row>

    /// Past this many moves in one level, `moveItem` one by one costs more than
    /// replacing the level and reloading it (measured: 960 moves 20 ms, 5,800
    /// moves about 300 ms), and the reload keeps what the person had by id: the
    /// nodes are the same objects, expansion and selection are synced after it.
    static var bulkMoveLimit: Int { 1_500 }
    private var lastSyncedExpansion: Set<Row.ID>?
    /// Where the person was looking when the rows around it all went away (a
    /// filter): kept until they come back, unless the person scrolls meanwhile.
    private var remembered: [Anchor] = []
    private var rememberedOrigin: CGFloat = 0

    init(coordinator: OutlineCoordinator<Row>) {
        self.coordinator = coordinator
    }

    private struct Anchor {
        let id: Row.ID
        /// The row's top, measured from the top of what is visible.
        let offset: CGFloat
    }

    private struct LevelWork {
        let parent: Node?
        let old: [Node]
        let new: [Node]
        let diff: OutlineDiff.Level<Row.ID>
    }

    /// A level that is replaced and reloaded instead of diffed: so many rows
    /// moved that reloading is cheaper than moving them one by one.
    private struct BulkLevel {
        let parent: Node?
        let new: [Node]
    }

    private struct Plan {
        var levels: [LevelWork] = []
        var bulk: [BulkLevel] = []
        /// Closed parents whose children changed: replaced, then reloaded with their children.
        var closedChanged: [Node] = []
        /// Rows whose triangle appeared or went.
        var expandabilityChanged: [Node] = []
    }

    func apply() {
        let c = coordinator
        let outline = c.outline
        c.isApplying = true
        defer { c.isApplying = false }

        // 1. where the person is looking, in the tree AppKit has now
        let anchors = captureAnchors()
        let selectedAnchor = captureSelectedAnchor()
        let clipOriginY = c.scrollView.contentView.bounds.origin.y
        if !remembered.isEmpty, abs(clipOriginY - rememberedOrigin) > 0.5 { remembered = [] }     // the person scrolled

        // 2, 3. stage and plan
        let configuration = c.configuration
        let counters = configuration.columns.compactMap(\.lines)       // only the columns that declare lines
        func lineCount(_ row: Row) -> Int {
            counters.reduce(1) { max($0, $1(row)) }
        }
        c.nodes.stage(rows: configuration.rows, children: configuration.children,
                      header: configuration.sectionHeader, lines: c.answersRowHeights ? lineCount : nil)
        var plan = Plan()
        if c.nodes.structureChanged {
            planLevel(parent: nil, old: c.nodes.roots, new: c.nodes.stagedRoots, into: &plan)
        }

        // 4. the changes, in one update
        if !plan.levels.isEmpty { execute(plan.levels) }
        c.nodes.commit()

        // 5. what the update could not reach
        for level in plan.bulk {
            modifyChildren(of: level.parent) { $0 = level.new }
            for node in level.new { adopt(node) }
            if let parent = level.parent { outline.reloadItem(parent, reloadChildren: true) } else { outline.reloadData() }
        }
        var reloaded = Set<ObjectIdentifier>()
        for node in plan.closedChanged {
            adopt(node)
            outline.reloadItem(node, reloadChildren: true)
            reloaded.insert(ObjectIdentifier(node))
        }
        for node in plan.expandabilityChanged where !reloaded.contains(ObjectIdentifier(node)) {
            outline.reloadItem(node)
        }

        // expansion only needs syncing when what is wanted changed or the tree did
        let desired = c.effectiveExpanded
        if c.nodes.structureChanged || desired != lastSyncedExpansion || !plan.bulk.isEmpty {
            syncExpansion(desired: desired)
            lastSyncedExpansion = desired
        }
        refreshVisibleValues()
        noteChangedHeights()
        syncSortIndicator()
        syncSelection()

        let isReorder = !plan.bulk.isEmpty || plan.levels.contains { $0.diff.moveCount > 0 }
        outline.layoutSubtreeIfNeeded()
        if !remembered.isEmpty, restoreScroll(anchors: remembered, keepingOffset: nil) {
            remembered = []                                                         // they are back
        } else {
            let found = restoreScroll(anchors: isReorder ? (selectedAnchor.map { [$0] } ?? []) : anchors,
                                      keepingOffset: isReorder && selectedAnchor == nil ? clipOriginY : nil)
            if !found, !isReorder, !anchors.isEmpty, remembered.isEmpty { remembered = anchors }
        }
        rememberedOrigin = c.scrollView.contentView.bounds.origin.y
    }

    // MARK: - planning

    private func ids(of nodes: [Node]) -> [Row.ID] { nodes.map(\.id) }

    private func sameNodes(_ a: [Node], _ b: [Node]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0 === $1 }
    }

    private func planLevel(parent: Node?, old: [Node], new: [Node], into plan: inout Plan) {
        // the same nodes in the same order (values only, the common update): no diff to compute
        let unchanged = sameNodes(old, new)
        var survivors = Set<Row.ID>()
        if !unchanged {
            let diff = OutlineDiff.level(old: ids(of: old), new: ids(of: new))
            if diff.moveCount > Self.bulkMoveLimit {
                plan.bulk.append(BulkLevel(parent: parent, new: new))
                return
            }
            if !diff.isUnchanged { plan.levels.append(LevelWork(parent: parent, old: old, new: new, diff: diff)) }
            survivors = Set(diff.survivorsOld)
        }
        for node in new where unchanged || survivors.contains(node.id) {
            let was = node.children, next = node.stagedChildren
            if was.isEmpty != next.isEmpty { plan.expandabilityChanged.append(node) }
            if !was.isEmpty, coordinator.outline.isItemExpanded(node) {
                planLevel(parent: node, old: was, new: next, into: &plan)    // its level may have changed
            } else if node.subtreeChanged {
                // closed: AppKit is not showing it, so it is taken over whole (every level below,
                // not only its children) and reloaded; opening it later shows the right rows
                plan.closedChanged.append(node)
            }
        }
    }

    // MARK: - execution

    private func modifyChildren(of parent: Node?, _ body: (inout [Node]) -> Void) {
        if let parent { body(&parent.children) } else { body(&coordinator.nodes.roots) }
    }

    /// A node that is new to AppKit brings its whole subtree as the caller
    /// described it; AppKit asks for those children only when the node opens.
    private func adopt(_ node: Node) {
        node.children = node.stagedChildren
        for child in node.children { adopt(child) }
    }

    private func execute(_ levels: [LevelWork]) {
        let outline = coordinator.outline
        outline.beginUpdates()

        // removals first, everywhere, so an id that moves between parents is
        // never in the tree twice
        for level in levels where !level.diff.removed.isEmpty {
            let gone = Set(level.diff.removed)
            let kept = level.old.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
            modifyChildren(of: level.parent) { $0 = kept }
            outline.removeItems(at: IndexSet(level.diff.removed), inParent: level.parent, withAnimation: [])
        }

        // survivors into their new relative order: only the ones outside the
        // longest increasing subsequence move, each once
        for level in levels where level.diff.moveCount > 0 {
            for move in OutlineDiff.moves(oldPositions: level.diff.oldPositions, stays: level.diff.stays) {
                modifyChildren(of: level.parent) { current in
                    let node = current.remove(at: move.from)
                    current.insert(node, at: move.to)
                }
                outline.moveItem(at: move.from, inParent: level.parent, to: move.to, inParent: level.parent)
            }
        }

        // inserts last, ascending: the survivors are in their final order, so
        // each new index is final
        for level in levels {
            for index in level.diff.inserted { adopt(level.new[index]) }
            modifyChildren(of: level.parent) { $0 = level.new }
            if !level.diff.inserted.isEmpty {
                outline.insertItems(at: IndexSet(level.diff.inserted), inParent: level.parent, withAnimation: [])
            }
        }
        outline.endUpdates()
    }

    // MARK: - expansion

    /// Opens every row in `desired` that is closed, parents before children, and
    /// closes every open row that is not. Ids that are not in the data are left
    /// alone (never pruned from the caller's set): filtering back reopens them.
    ///
    /// Level by level, and within a level from the bottom up, inside one update:
    /// each row opens into the row list below it, so opening the last one first
    /// leaves the fewest rows to shift. Opened top-down, a thousand groups cost
    /// about 0.3 ms each; bottom-up, about a tenth of that.
    private func syncExpansion(desired: Set<Row.ID>) {
        let c = coordinator
        let outline = c.outline
        outline.beginUpdates()
        var level = c.nodes.roots
        while !level.isEmpty {
            var toExpand: [Node] = []
            for node in level where node.isExpandable {
                let wanted = desired.contains(node.id)
                let isOpen = outline.isItemExpanded(node)
                if wanted && !isOpen { toExpand.append(node) } else if !wanted && isOpen { outline.collapseItem(node) }
            }
            for node in toExpand.reversed() { outline.expandItem(node) }
            level = level.filter { $0.isExpandable && desired.contains($0.id) }.flatMap(\.children)
        }
        outline.endUpdates()
    }

    // MARK: - values, selection, sort

    /// Puts the current values into the cells that are on screen, in place: the
    /// cells stay, so AppKit has no row to rebuild and nothing to lay out unless a
    /// cell's own size changed. A section header row is reloaded (its model is
    /// not a column's).
    func refreshVisibleValues() {
        let c = coordinator
        let outline = c.outline
        let visible = outline.rows(in: outline.visibleRect)
        guard visible.length > 0, outline.numberOfColumns > 0 else { return }
        let rows = visible.location..<(visible.location + visible.length)
        var headerRows = IndexSet()
        for row in rows {
            guard let node = outline.item(atRow: row) as? Node else { continue }
            if node.header != nil { headerRows.insert(row); continue }
            for (index, tableColumn) in outline.tableColumns.enumerated() where !tableColumn.isHidden {
                guard let definition = c.definition(for: tableColumn),
                      let cell = outline.view(atColumn: index, row: row, makeIfNecessary: false) as? OutlineCell else { continue }
                c.configure(cell, for: node, definition: definition)
            }
        }
        if !headerRows.isEmpty {
            outline.reloadData(forRowIndexes: headerRows, columnIndexes: IndexSet(integersIn: 0..<outline.numberOfColumns))
        }
    }

    /// A row whose line count changed gets its height measured again, on screen or
    /// not: a row that scrolls in later must not keep the old height.
    private func noteChangedHeights() {
        let c = coordinator
        var rows = IndexSet()
        for node in c.nodes.linesChanged {
            let row = c.outline.row(forItem: node)
            if row >= 0 { rows.insert(row) }
        }
        if !rows.isEmpty { c.outline.noteHeightOfRows(withIndexesChanged: rows) }
    }

    private func syncSortIndicator() {
        let c = coordinator
        guard c.configuration.sortOrder != nil else { return }
        let wanted = OutlineSortMapping.descriptors(for: c.effectiveSortOrder, columns: c.configuration.columns)
        if c.outline.sortDescriptors != wanted { c.outline.sortDescriptors = wanted }
    }

    /// Selects what the caller selects. A row that was selected and is gone (or
    /// is hidden under a closed parent) leaves the selection, and the binding
    /// hears it; an id that was never matched (data still loading) is left alone.
    private func syncSelection() {
        let c = coordinator
        let outline = c.outline
        let desired = c.effectiveSelection
        var rows = IndexSet()
        for id in desired {
            guard let node = c.nodes.node(for: id), node.header == nil else { continue }
            let row = outline.row(forItem: node)
            if row >= 0 { rows.insert(row) }
        }
        if rows != outline.selectedRowIndexes { outline.selectRowIndexes(rows, byExtendingSelection: false) }
        let actual = c.selectedIDs()
        let dropped = c.knownSelection.subtracting(actual)
        c.knownSelection = actual
        if !dropped.isEmpty {
            c.pending.selection = desired.subtracting(dropped)
            c.scheduleFlush()
        }
    }

    // MARK: - scroll

    private func visibleRowRange() -> Range<Int> {
        let outline = coordinator.outline
        let range = outline.rows(in: outline.visibleRect)
        return range.location..<(range.location + range.length)
    }

    /// The first fully visible row and the few above it, nearest first, each
    /// with its distance from the top of what is visible. The extra rows are
    /// for when the first one is removed: the nearest survivor above is used.
    private func captureAnchors() -> [Anchor] {
        let outline = coordinator.outline
        let top = outline.visibleRect.minY
        let rows = visibleRowRange()
        guard let first = rows.first(where: { outline.rect(ofRow: $0).minY >= top - 0.5 }) else { return [] }
        return stride(from: first, through: max(0, first - 20), by: -1).compactMap { row in
            guard let node = outline.item(atRow: row) as? Node else { return nil }
            return Anchor(id: node.id, offset: outline.rect(ofRow: row).minY - top)
        }
    }

    /// The first selected row that is visible: a re-sort keeps it where it was on screen.
    private func captureSelectedAnchor() -> Anchor? {
        let outline = coordinator.outline
        let top = outline.visibleRect.minY
        for row in visibleRowRange() where outline.isRowSelected(row) {
            if let node = outline.item(atRow: row) as? Node { return Anchor(id: node.id, offset: outline.rect(ofRow: row).minY - top) }
        }
        return nil
    }

    /// Returns whether it found something to hold still: an anchor that still has a row.
    @discardableResult
    private func restoreScroll(anchors: [Anchor], keepingOffset: CGFloat?) -> Bool {
        let c = coordinator
        let outline = c.outline
        let clip = c.scrollView.contentView
        var target: CGFloat?
        if let keepingOffset {
            target = keepingOffset
        } else {
            for anchor in anchors {
                guard let node = c.nodes.node(for: anchor.id) else { continue }
                let row = outline.row(forItem: node)
                guard row >= 0 else { continue }
                let nowOffset = outline.rect(ofRow: row).minY - outline.visibleRect.minY
                target = clip.bounds.origin.y + (nowOffset - anchor.offset)
                break
            }
        }
        guard let target else { return false }
        let insets = c.scrollView.contentInsets
        let lowest = -insets.top
        let highest = max(lowest, outline.frame.height - clip.bounds.height + insets.bottom)
        let clamped = min(max(target, lowest), highest)
        guard abs(clamped - clip.bounds.origin.y) > 0.5 else { return true }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: clamped))
        c.scrollView.reflectScrolledClipView(clip)
        return true
    }
}
