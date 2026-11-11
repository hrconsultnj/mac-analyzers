import SwiftUI

/// A sortable table whose rows can open, on AppKit's outline.
///
/// Why not SwiftUI's `Table` with `DisclosureTableRow`, `Table(children:)` or a
/// `List` of `OutlineGroup`s: every one of them makes AppKit log "reentrant
/// operation in its NSTableView delegate" on open-all and on an in-place
/// re-sort (measured; `tasks-plans/research/app/outline-table-reentrancy-*`),
/// and a warning is a defect here. A wrapped `NSOutlineView` logs none and
/// updates about ten times faster.
///
/// The folder, by job:
/// - this file: the public view, its initialisers and modifiers;
/// - `OutlineColumn`, `OutlineTicks`, `OutlineSectionHeader`,
///   `RememberedExpansion`, `OutlineGroupCell`, `OutlineFolding`: the pieces a
///   caller declares with;
/// - `OutlineRepresentable`, `OutlineCoordinator` (+ `Cells`, `Events`),
///   `OutlineUpdater`: the AppKit side. AppKit is changed only by the updater,
///   never while AppKit is calling in, and every write back to a binding
///   happens on the next main turn.
public struct OutlineTable<Row: Identifiable>: View {
    var configuration: OutlineConfiguration<Row>
    var empty: (isLoading: Bool, content: AnyView)?

    // MARK: - initialisers (multiple selection / single selection, sorted / not)

    public init(_ rows: [Row],
                children: KeyPath<Row, [Row]?>,
                selection: Binding<Set<Row.ID>>,
                sortOrder: Binding<[KeyPathComparator<Row>]>,
                expanded: Binding<Set<Row.ID>>,
                autosave: String,
                @OutlineColumnBuilder<Row> columns: () -> [OutlineColumn<Row>]) {
        self.init(rows, children: children,
                  selection: OutlineSelection(allowsMultiple: true, get: { selection.wrappedValue },
                                              set: { selection.wrappedValue = $0 }),
                  sortOrder: sortOrder, expanded: expanded, autosave: autosave, columns: columns())
    }

    public init(_ rows: [Row],
                children: KeyPath<Row, [Row]?>,
                selection: Binding<Row.ID?>,
                sortOrder: Binding<[KeyPathComparator<Row>]>,
                expanded: Binding<Set<Row.ID>>,
                autosave: String,
                @OutlineColumnBuilder<Row> columns: () -> [OutlineColumn<Row>]) {
        self.init(rows, children: children, selection: Self.single(selection),
                  sortOrder: sortOrder, expanded: expanded, autosave: autosave, columns: columns())
    }

    /// No sorting: a history in the order it was given.
    public init(_ rows: [Row],
                children: KeyPath<Row, [Row]?>,
                selection: Binding<Set<Row.ID>>,
                expanded: Binding<Set<Row.ID>>,
                autosave: String,
                @OutlineColumnBuilder<Row> columns: () -> [OutlineColumn<Row>]) {
        self.init(rows, children: children,
                  selection: OutlineSelection(allowsMultiple: true, get: { selection.wrappedValue },
                                              set: { selection.wrappedValue = $0 }),
                  sortOrder: nil, expanded: expanded, autosave: autosave, columns: columns())
    }

    /// Single selection, no sorting.
    public init(_ rows: [Row],
                children: KeyPath<Row, [Row]?>,
                selection: Binding<Row.ID?>,
                expanded: Binding<Set<Row.ID>>,
                autosave: String,
                @OutlineColumnBuilder<Row> columns: () -> [OutlineColumn<Row>]) {
        self.init(rows, children: children, selection: Self.single(selection),
                  sortOrder: nil, expanded: expanded, autosave: autosave, columns: columns())
    }

    private init(_ rows: [Row], children: KeyPath<Row, [Row]?>, selection: OutlineSelection<Row.ID>,
                 sortOrder: Binding<[KeyPathComparator<Row>]>?, expanded: Binding<Set<Row.ID>>,
                 autosave: String, columns: [OutlineColumn<Row>]) {
        configuration = OutlineConfiguration(rows: rows, children: children, selection: selection,
                                             sortOrder: sortOrder, expanded: expanded, autosave: autosave,
                                             columns: columns)
    }

    private static func single(_ binding: Binding<Row.ID?>) -> OutlineSelection<Row.ID> {
        OutlineSelection(allowsMultiple: false,
                         get: { binding.wrappedValue.map { [$0] } ?? [] },
                         set: { binding.wrappedValue = $0.first })
    }

    // MARK: - modifiers

    /// Right-click menu. `ids` is the clicked row alone when it is outside the
    /// selection, otherwise the whole selection (AppKit's rule). Without
    /// `primaryAction`, a double-click on a group row opens or closes it.
    public func contextMenu<M: View>(@ViewBuilder _ menu: @escaping @MainActor (Set<Row.ID>) -> M,
                                     primaryAction: (@MainActor (Set<Row.ID>) -> Void)? = nil) -> Self {
        var copy = self
        copy.configuration.menu = { AnyView(menu($0)) }
        copy.configuration.primaryAction = primaryAction
        return copy
    }

    /// A tick per row.
    public func ticks(_ ticks: OutlineTicks<Row>) -> Self {
        var copy = self
        copy.configuration.ticks = ticks
        return copy
    }

    /// Rows drawn dimmed. They can still be selected, so the inspector can say why.
    public func rowEnabled(_ isEnabled: @escaping @MainActor (Row) -> Bool) -> Self {
        var copy = self
        copy.configuration.rowEnabled = isEnabled
        return copy
    }

    /// Rows drawn as a full-width section header (a day in a history).
    public func sectionHeader(_ header: @escaping @MainActor (Row) -> OutlineSectionHeader?) -> Self {
        var copy = self
        copy.configuration.sectionHeader = header
        return copy
    }

    /// Shown in place of the rows while `rows` is empty (a progress indicator
    /// while `isLoading`). The outline stays mounted underneath.
    public func emptyContent<E: View>(isLoading: Bool, @ViewBuilder _ empty: () -> E) -> Self {
        var copy = self
        copy.empty = (isLoading, AnyView(empty()))
        return copy
    }

    public func columnHeaders(_ visibility: Visibility) -> Self {
        var copy = self
        copy.configuration.showsColumnHeaders = visibility != .hidden
        return copy
    }

    public func alternatingRows(_ on: Bool) -> Self {
        var copy = self
        copy.configuration.alternatingRows = on
        return copy
    }

    public var body: some View {
        ZStack {
            OutlineRepresentable(configuration: configuration)
            if configuration.rows.isEmpty, let empty {
                if empty.isLoading { ProgressView() } else { empty.content }
            }
        }
    }
}
