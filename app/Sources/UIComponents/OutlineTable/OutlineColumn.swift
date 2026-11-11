import SwiftUI

/// The system colour a text cell is drawn in. Names a role, never a value.
public enum OutlineTextStyle: Sendable, Equatable {
    case primary, secondary, tertiary, warning, critical
}

/// One column of an `OutlineTable`, declared the way `Table` declares one.
public struct OutlineColumn<Row: Identifiable> {

    enum Cell {
        /// A SwiftUI cell, hosted in a reused `NSHostingView`.
        case view(@MainActor (Row) -> AnyView)
        /// Plain text: an `NSTextField` label, no hosting.
        case text(@MainActor (Row) -> String)
    }

    /// The column's identity for sorting and autosave, so it never changes.
    let id: String
    let title: String
    let comparator: KeyPathComparator<Row>?
    let cell: Cell
    var minWidth: CGFloat?
    var idealWidth: CGFloat?
    var maxWidth: CGFloat?
    var horizontalAlignment: HorizontalAlignment = .leading
    var style: (@MainActor (Row) -> OutlineTextStyle)?
    var usesMonospacedDigits = false
    var startsHidden = false
    var canHide = true
    var tooltip: (@MainActor (Row) -> String?)?
    var typeSelect: (@MainActor (Row) -> String)?
    var lines: (@MainActor (Row) -> Int)?

    /// A SwiftUI cell, hosted in a reused `NSHostingView` (one per visible cell,
    /// its root view replaced as the cell is reused).
    public init<C: View>(_ id: String, _ title: String,
                         sortUsing comparator: KeyPathComparator<Row>? = nil,
                         @ViewBuilder content: @escaping @MainActor (Row) -> C) {
        self.id = id
        self.title = title
        self.comparator = comparator
        self.cell = .view { AnyView(content($0)) }
    }

    /// The plain-text fast path: a label, no hosting.
    public init(_ id: String, _ title: String,
                text: @escaping @MainActor (Row) -> String,
                sortUsing comparator: KeyPathComparator<Row>? = nil) {
        self.id = id
        self.title = title
        self.comparator = comparator
        self.cell = .text(text)
    }

    // MARK: - modifiers

    public func width(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> Self {
        var copy = self
        copy.minWidth = min
        copy.idealWidth = ideal
        copy.maxWidth = max
        return copy
    }

    /// Cell and header alignment; `.trailing` for numbers.
    public func alignment(_ alignment: HorizontalAlignment) -> Self {
        var copy = self
        copy.horizontalAlignment = alignment
        return copy
    }

    /// The colour of a text cell. Has no effect on a SwiftUI cell.
    public func textStyle(_ style: @escaping @MainActor (Row) -> OutlineTextStyle) -> Self {
        var copy = self
        copy.style = style
        return copy
    }

    public func monospacedDigits() -> Self {
        var copy = self
        copy.usesMonospacedDigits = true
        return copy
    }

    /// Hidden until the person shows it from the header's menu.
    public func defaultHidden() -> Self {
        var copy = self
        copy.startsHidden = true
        return copy
    }

    /// Whether the header's menu offers to hide this column (default true;
    /// the first column is never hideable, whatever this says).
    public func hideable(_ on: Bool) -> Self {
        var copy = self
        copy.canHide = on
        return copy
    }

    public func help(_ tooltip: @escaping @MainActor (Row) -> String?) -> Self {
        var copy = self
        copy.tooltip = tooltip
        return copy
    }

    /// How many lines of text this column's cell shows for a row (default one).
    /// A row is as tall as the standard row plus the extra lines of its tallest
    /// cell, measured in the system font: automatic row heights are not used,
    /// because AppKit's measuring pass logs "reentrant operation" on bulk
    /// changes (see `OutlineCoordinator`).
    public func lines(_ count: @escaping @MainActor (Row) -> Int) -> Self {
        var copy = self
        copy.lines = count
        return copy
    }

    /// What typing the first letters of a name jumps to, for a SwiftUI first
    /// column. A text first column uses its text.
    public func typeSelect(_ string: @escaping @MainActor (Row) -> String) -> Self {
        var copy = self
        copy.typeSelect = string
        return copy
    }
}

@resultBuilder
public enum OutlineColumnBuilder<Row: Identifiable> {
    public static func buildExpression(_ column: OutlineColumn<Row>) -> [OutlineColumn<Row>] { [column] }
    public static func buildExpression(_ columns: [OutlineColumn<Row>]) -> [OutlineColumn<Row>] { columns }
    public static func buildBlock(_ parts: [OutlineColumn<Row>]...) -> [OutlineColumn<Row>] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [OutlineColumn<Row>]?) -> [OutlineColumn<Row>] { part ?? [] }
    public static func buildEither(first part: [OutlineColumn<Row>]) -> [OutlineColumn<Row>] { part }
    public static func buildEither(second part: [OutlineColumn<Row>]) -> [OutlineColumn<Row>] { part }
    public static func buildArray(_ parts: [[OutlineColumn<Row>]]) -> [OutlineColumn<Row>] { parts.flatMap { $0 } }
}
