import AppKit

/// Makes the columns fit the table's width, the way the declaration says (`OutlineColumnFit`).
///
/// - An optional column is hidden when the columns that stay would not fit, rightmost first, and
///   shown again when there is room, leftmost of the hidden ones first. A person's choice from the
///   header's menu always wins over this: hidden by a person stays hidden, shown by a person stays
///   shown. What a person chose is kept in this table's own defaults key, and AppKit's saved
///   hidden flag is not trusted for an optional column (it also records what THIS did).
/// - An essential column is never hidden. When even with every optional column gone the columns do
///   not fit, the essential ones (not the first) give up width down to their minimum, rightmost first.
/// - The first column is the flexible one: AppKit gives it the spare width and takes it back down to its
///   minimum, which is what is counted here.
///
/// Runs on the main turn after the table's size changed, never inside one of AppKit's callbacks.
@MainActor
final class OutlineFitter {
    private let outline: NSOutlineView
    private let scrollView: NSScrollView
    /// Optional columns the room, not the person, hid.
    private(set) var autoHidden: [String] = []
    /// Optional columns a person hid, and ones a person showed.
    private var personHidden: Set<String> = []
    private var personShown: Set<String> = []
    private var key = ""
    /// The columns as declared (id, fit, minimum width), in declared order.
    private var columns: [(id: String, fit: OutlineColumnFit, minimum: CGFloat, startsHidden: Bool)] = []
    private var queued = false
    /// What the inset style adds at the table's edge, measured: with none of it counted the last column
    /// ends 5 points past the visible rect.
    private static let edge: CGFloat = 5
    /// Asked before a fit changes anything: false while AppKit is calling in, nil when the table that
    /// owned this is gone (then nothing is done and nothing is queued again).
    var mayChangeColumns: () -> Bool? = { true }

    init(outline: NSOutlineView, scrollView: NSScrollView) {
        self.outline = outline
        self.scrollView = scrollView
    }

    /// Called when the columns are built, after AppKit restored its own saved state.
    func configure<Row: Identifiable>(_ definitions: [OutlineColumn<Row>], autosave: String) {
        key = "OutlineTable.\(autosave).hiddenByPerson"
        columns = definitions.map { ($0.id, $0.fit, $0.minWidth ?? 40, $0.startsHidden) }
        autoHidden = []
        personShown = []
        let optional = columns.filter { $0.fit == .optional }
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            personHidden = Set(saved)
        } else {
            personHidden = Set(optional.filter(\.startsHidden).map(\.id))
        }
        for column in optional { column.id.withColumn(outline) { $0.isHidden = personHidden.contains(column.id) } }
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView.contentView,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        // a person resizing a column gives the first one what is left, as a window resize does
        NotificationCenter.default.addObserver(forName: NSTableView.columnDidResizeNotification, object: outline,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        schedule()
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: the header menu

    func isOptional(_ id: String) -> Bool { columns.first { $0.id == id }?.fit == .optional }

    /// What the menu shows: a checkmark when the column is on screen.
    func isShown(_ id: String) -> Bool {
        outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id)).map { !$0.isHidden } ?? false
    }

    /// The menu's choice for an optional column: a person's decision.
    func toggle(_ id: String) {
        guard isOptional(id) else { return }
        if isShown(id) {
            personHidden.insert(id); personShown.remove(id)
        } else {
            personHidden.remove(id); personShown.insert(id)
        }
        autoHidden.removeAll { $0 == id }
        UserDefaults.standard.set(personHidden.sorted(), forKey: key)
        id.withColumn(outline) { $0.isHidden = personHidden.contains(id) }
        schedule()
    }

    // MARK: fitting

    func schedule() {
        guard !queued else { return }
        queued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.queued = false
                switch self.mayChangeColumns() {
                case nil: return                    // the table is gone
                case false?: self.schedule()        // AppKit is calling in: next turn
                case true?: self.fit()
                }
            }
        }
    }

    /// Room for the columns now: the clip's width less the table style's own side padding.
    private var available: CGFloat { scrollView.contentView.bounds.width }

    private func width(of id: String) -> CGFloat {
        outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))?.width ?? 0
    }

    /// What the visible columns need: the first at `firstWidth` (its minimum unless asked), the others
    /// at their widths, and the spacing between them.
    private func needed(extra: String? = nil, firstWidth: CGFloat? = nil) -> CGFloat {
        guard let first = columns.first else { return 0 }
        var total = firstWidth ?? first.minimum
        var count = 1
        for column in columns.dropFirst() where isShown(column.id) || column.id == extra {
            total += column.id == extra ? max(width(of: column.id), column.minimum) : width(of: column.id)
            count += 1
        }
        return total + CGFloat(count) * outline.intercellSpacing.width + Self.edge
    }

    func fit() {
        guard columns.count > 1, available > 0 else { return }
        // 1. hide optional columns, rightmost first, while the rest does not fit
        for column in columns.reversed() where column.fit == .optional && needed() > available {
            guard isShown(column.id), !personShown.contains(column.id), !personHidden.contains(column.id) else { continue }
            column.id.withColumn(outline) { $0.isHidden = true }
            autoHidden.append(column.id)
        }
        // 2. show them again, leftmost of the hidden first, while they fit
        for id in autoHidden.sorted(by: { order($0) < order($1) }) where needed(extra: id) <= available {
            id.withColumn(outline) { $0.isHidden = false }
            autoHidden.removeAll { $0 == id }
        }
        // the first column takes what is left, down to its minimum: AppKit does not give it back
        // what a narrower window took, nor give it what a hidden column freed
        if let first = columns.first, let table = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(first.id)) {
            let others = needed(firstWidth: 0)
            let wanted = min(max(available - others, max(table.minWidth, first.minimum)), table.maxWidth)
            if abs(table.width - wanted) > 0.5 { table.width = wanted }
        }
        // 3. still too wide: the essential columns give up width, rightmost first, down to their minimum
        var deficit = needed() - available
        if deficit > 0 {
            for column in columns.dropFirst().reversed() where column.fit == .essential && isShown(column.id) && deficit > 0 {
                guard let table = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(column.id)) else { continue }
                let cut = min(table.width - max(table.minWidth, column.minimum), deficit)
                if cut > 0 { table.width -= cut; deficit -= cut }
            }
        }
    }

    private func order(_ id: String) -> Int { columns.firstIndex { $0.id == id } ?? 0 }
}

private extension String {
    @MainActor func withColumn(_ outline: NSOutlineView, _ change: (NSTableColumn) -> Void) {
        guard let column = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(self)) else { return }
        change(column)
    }
}
