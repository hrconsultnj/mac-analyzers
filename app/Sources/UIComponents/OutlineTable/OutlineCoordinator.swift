import AppKit
import os
import SwiftUI

/// AppKit's data source and delegate for the outline. It answers AppKit from the
/// node tree and nothing else; changing what AppKit holds is the updater's job
/// alone, and only while AppKit is not calling in here.
@MainActor
final class OutlineCoordinator<Row: Identifiable>: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    typealias Node = OutlineNode<Row>

    let scrollView = NSScrollView()
    let outline = OutlineNSView()
    let nodes: OutlineNodes<Row>
    let headerMenu: OutlineHeaderMenu
    let fitter: OutlineFitter
    private(set) var updater: OutlineUpdater<Row>!

    var configuration: OutlineConfiguration<Row>
    var environment = EnvironmentValues()

    // MARK: rule 1 — AppKit is changed only by the updater, never while AppKit calls us

    /// Raised on entry to every data-source and delegate method, lowered on exit.
    private(set) var depth = 0
    /// True while the updater runs: AppKit's notifications caused by our own
    /// changes are not the person's and are not echoed to the caller.
    var isApplying = false
    private var applyQueued = false

    // MARK: rule 2 — every write to a caller's binding happens on the next main turn

    var pending = OutlinePending<Row>()
    var flushIsQueued = false
    /// What AppKit has selected, as of the last sync or the last notification.
    var knownSelection: Set<Row.ID> = []

    var columnIDs: [String] = []
    /// Whether the delegate answers `heightOfRowByItem`. AppKit asks that for
    /// every row after every structural change, so a table whose rows are all
    /// the standard height does not answer it at all (measured: moving 1,000
    /// rows cost 280 ms with it, 17 ms without).
    private(set) var answersRowHeights = false
    /// Whether the delegate answers `isGroupItem` and `shouldSelectItem`, which
    /// only a table with section headers needs. Same reason.
    private var answersHeaders = false
    private(set) var columnsBuilt = false

    static var log: Logger { Logger(subsystem: "com.mac-analyzers.app", category: "outline") }

    init(configuration: OutlineConfiguration<Row>) {
        self.configuration = configuration
        nodes = OutlineNodes<Row>()
        headerMenu = OutlineHeaderMenu(outline: outline)
        fitter = OutlineFitter(outline: outline, scrollView: scrollView)
        super.init()
        fitter.mayChangeColumns = { [unowned self] in self.depth == 0 && !self.isApplying }
        headerMenu.fitter = fitter
        updater = OutlineUpdater(coordinator: self)
        outline.dataSource = self
        outline.delegate = self
        outline.style = .inset
        outline.rowSizeStyle = .default
        // Not automatic: AppKit's measuring pass for automatic row heights logs
        // "reentrant operation in its NSTableView delegate" on expand-all and on a
        // re-sort of this wrapper (measured: A1 with automatic heights warns once
        // on each, without them never). Heights come from `outlineView(_:heightOfRowByItem:)`.
        outline.usesAutomaticRowHeights = false
        outline.allowsColumnReordering = true
        outline.allowsColumnResizing = true
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle     // the first column takes the spare width, as in Finder and Activity Monitor
        outline.allowsEmptySelection = true
        outline.allowsTypeSelect = true
        outline.autosaveExpandedItems = false
        outline.doubleAction = #selector(doubleClicked(_:))
        outline.target = self
        outline.onPrimaryKey = { [unowned self] in self.primaryKey() }
        outline.onSpaceKey = { [unowned self] in self.spaceKey() }
        outline.menuProvider = { [unowned self] event in self.contextMenu(for: event) }
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = true
    }

    /// AppKit asks this on the main thread when the delegate is set.
    override nonisolated func responds(to aSelector: Selector!) -> Bool {
        MainActor.assumeIsolated {
            if aSelector == #selector(NSOutlineViewDelegate.outlineView(_:heightOfRowByItem:)) { return answersRowHeights }
            if aSelector == #selector(NSOutlineViewDelegate.outlineView(_:isGroupItem:))
                || aSelector == #selector(NSOutlineViewDelegate.outlineView(_:shouldSelectItem:)) { return answersHeaders }
            return super.responds(to: aSelector)
        }
    }

    /// AppKit records which delegate methods exist when the delegate is set, so
    /// a change in what the table needs sets it again.
    private func updateRowHeightAnswering() {
        let needed = configuration.columns.contains { $0.lines != nil }
        let headers = configuration.sectionHeader != nil
        guard needed != answersRowHeights || headers != answersHeaders else { return }
        answersRowHeights = needed
        answersHeaders = headers
        outline.delegate = nil
        outline.delegate = self
        outline.reloadData()
    }

    // MARK: - AppKit actions (in the class body: @objc is not allowed in an extension of a generic class)

    @objc func doubleClicked(_ sender: Any?) { handleDoubleClick() }
    @objc func tickClicked(_ sender: NSButton) { handleTick(sender) }

    // MARK: - updates from SwiftUI

    func update(_ configuration: OutlineConfiguration<Row>, environment: EnvironmentValues) {
        self.configuration = configuration
        self.environment = environment
        requestApply()
    }

    /// Applies now, or on the next main turn when AppKit is calling us (an
    /// update that arrives inside a callback because something synchronous
    /// caused it) or an update is already running.
    func requestApply() {
        if depth > 0 || isApplying {
            queueApply()
            return
        }
        apply()
    }

    private func queueApply() {
        guard !applyQueued else { return }
        applyQueued = true
        Self.log.notice("OutlineTable: update queued to the next main turn because AppKit was calling in")
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                applyQueued = false
                requestApply()
            }
        }
    }

    private func apply() {
        configureAppearance()
        buildColumnsIfNeeded()
        updater.apply()
    }

    /// Everything about the outline that follows the environment and the modifiers.
    private func configureAppearance() {
        // each only when it differs: AppKit treats even an unchanged assignment as a change
        let rowSize: NSTableView.RowSizeStyle
        switch environment.controlSize {
        case .mini, .small: rowSize = .small
        case .large, .extraLarge: rowSize = .large
        default: rowSize = .default
        }
        if outline.rowSizeStyle != rowSize { outline.rowSizeStyle = rowSize }
        if outline.allowsMultipleSelection != configuration.selection.allowsMultiple {
            outline.allowsMultipleSelection = configuration.selection.allowsMultiple
        }
        if outline.usesAlternatingRowBackgroundColors != configuration.alternatingRows {
            outline.usesAlternatingRowBackgroundColors = configuration.alternatingRows
        }
        if configuration.showsColumnHeaders {
            if outline.headerView == nil {
                outline.headerView = NSTableHeaderView()
                outline.headerView?.menu = headerMenu.menu
            }
        } else if outline.headerView != nil {
            outline.headerView = nil
        }
        // the header AppKit gives a new outline has no menu of ours: the columns' menu is this one
        if let header = outline.headerView, header.menu !== headerMenu.menu { header.menu = headerMenu.menu }
    }

    // MARK: - columns

    /// Builds the outline's columns from the declaration the first time, then
    /// sets the autosave name AFTER they exist, so saved widths, order and
    /// hidden state are restored onto them.
    private func buildColumnsIfNeeded() {
        let ids = configuration.columns.map(\.id)
        updateRowHeightAnswering()
        if columnsBuilt, ids == columnIDs {
            // by identifier: the columns are in the order the person dragged them to, not the declared one
            for definition in configuration.columns {
                if let column = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(definition.id)),
                   column.title != definition.title { column.title = definition.title }
            }
            return
        }
        for column in outline.tableColumns { outline.removeTableColumn(column) }
        for definition in configuration.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(definition.id))
            column.title = definition.title
            let minimum = definition.minWidth ?? 40
            column.minWidth = minimum
            column.width = max(definition.idealWidth ?? column.width, minimum)      // undeclared: AppKit's own default width
            column.maxWidth = definition.maxWidth ?? 10_000
            column.isHidden = definition.startsHidden
            column.sortDescriptorPrototype = OutlineSortMapping.prototype(for: definition)
            column.headerCell.alignment = definition.horizontalAlignment == .trailing ? .right : .left
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns.first
        headerMenu.configure(hideable: configuration.columns.enumerated().compactMap { index, definition in
            index > 0 && definition.canHide && !definition.title.isEmpty ? (definition.id, definition.title) : nil
        })
        columnIDs = ids
        columnsBuilt = true
        outline.autosaveName = "OutlineTable.\(configuration.autosave)"
        outline.autosaveTableColumns = true
        // after AppKit restored its saved state: what the declaration says about room is applied over it
        fitter.configure(configuration.columns, autosave: configuration.autosave)
    }

    func definition(for column: NSTableColumn) -> OutlineColumn<Row>? {
        configuration.columns.first { $0.id == column.identifier.rawValue }
    }

    // MARK: - NSOutlineViewDataSource

    /// Every item AppKit holds was handed to it by this coordinator, so it is a
    /// `Node`: no checked cast. AppKit asks these questions many times per row, and
    /// a checked cast to a generic class costs more than the answer.
    @inline(__always)
    private func asNode(_ item: Any) -> Node {
        unsafeDowncast(item as AnyObject, to: Node.self)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        depth += 1
        defer { depth -= 1 }
        guard let item else { return nodes.roots.count }
        return asNode(item).children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        depth += 1
        defer { depth -= 1 }
        guard let item else { return nodes.roots[index] }
        return asNode(item).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        depth += 1
        defer { depth -= 1 }
        return asNode(item).isExpandable
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        depth += 1
        defer { depth -= 1 }
        let node = asNode(item)
        if let header = node.header {
            let cell = (outlineView.makeView(withIdentifier: OutlineSectionHeaderCell.identifier, owner: self)
                        as? OutlineSectionHeaderCell) ?? OutlineSectionHeaderCell(frame: .zero)
            cell.configure(header)
            return cell
        }
        guard let tableColumn, let definition = definition(for: tableColumn) else { return nil }
        return cell(for: node, column: tableColumn, definition: definition)
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        depth += 1
        defer { depth -= 1 }
        let standard = outlineView.rowHeight                // the system's, for the row size style
        let node = asNode(item)
        guard node.header == nil else { return standard }
        var tallest = 1
        for definition in configuration.columns {
            if let lines = definition.lines { tallest = max(tallest, lines(node.row)) }
        }
        guard tallest > 1 else { return standard }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        return standard + CGFloat(tallest - 1) * NSLayoutManager().defaultLineHeight(for: font)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        depth += 1
        defer { depth -= 1 }
        return asNode(item).header != nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        depth += 1
        defer { depth -= 1 }
        return asNode(item).header == nil
    }

    func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
        depth += 1
        defer { depth -= 1 }
        let node = asNode(item)
        for definition in configuration.columns {
            if let typeSelect = definition.typeSelect { return typeSelect(node.row) }
            if case .text(let text) = definition.cell { return text(node.row) }
        }
        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
        depth += 1
        defer { depth -= 1 }
        return columnIndex != 0 && newColumnIndex != 0          // the first column carries the hierarchy
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        depth += 1
        defer { depth -= 1 }
        sortDescriptorsDidChange()
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        depth += 1
        defer { depth -= 1 }
        selectionDidChange()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        depth += 1
        defer { depth -= 1 }
        expansionDidChange(notification, opened: true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        depth += 1
        defer { depth -= 1 }
        expansionDidChange(notification, opened: false)
    }
}
