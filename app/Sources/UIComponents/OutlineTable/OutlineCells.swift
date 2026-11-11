import AppKit
import SwiftUI

/// The root of a hosted cell. A hosted cell is a new SwiftUI root, so it does
/// not inherit the environment of the table; this puts the table's environment
/// (control size, colour scheme, the observable objects a cell reads) back.
struct OutlineHostedRoot: View {
    let content: AnyView
    let environment: EnvironmentValues
    let isEnabled: Bool
    /// The cell's own: the appearance of the window it is drawn in, which the
    /// table's environment may not have caught up with yet.
    @Environment(\.colorScheme) private var ownColorScheme

    var body: some View {
        let own = ownColorScheme
        content
            .disabled(!isEnabled)
            .accessibilityElement(children: .combine)
            .transformEnvironment(\.self) { $0 = environment; $0.colorScheme = own }
    }
}

/// The root of a context menu built from SwiftUI, with the same environment.
struct OutlineMenuRoot: View {
    let content: AnyView
    let environment: EnvironmentValues

    var body: some View {
        content.transformEnvironment(\.self) { $0 = environment }
    }
}

/// A cell of the table: an optional tick, then the content, which is either a
/// text label (no hosting) or one reused `NSHostingView` whose root view is
/// replaced as the cell is reused.
@MainActor
final class OutlineCell: NSTableCellView {

    enum Kind { case text, view }

    let kind: Kind
    /// Only a table with ticks has checkboxes, and only the first column's cells.
    let checkbox: NSButton?
    private let label: NSTextField?
    private var host: NSHostingView<OutlineHostedRoot>?

    static func identifier(column: String, kind: Kind, hasTick: Bool) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("outline-\(kind == .text ? "t" : "v")\(hasTick ? "k" : "")-\(column)")
    }

    init(identifier: NSUserInterfaceItemIdentifier, kind: Kind, hasTick: Bool, target: AnyObject, action: Selector) {
        self.kind = kind
        let box: NSButton? = hasTick ? NSButton(checkboxWithTitle: "", target: target, action: action) : nil
        checkbox = box
        label = kind == .text ? NSTextField(labelWithString: "") : nil
        super.init(frame: .zero)
        self.identifier = identifier

        // Plain constraints, no stack view: a cell is made for every visible row
        // each time a re-sort or an expand-all replaces them, and a stack view with
        // a checkbox behind it made that the slowest part of an update.
        var leading = leadingAnchor
        if let box {
            box.allowsMixedState = true
            box.imagePosition = .imageOnly
            box.refusesFirstResponder = true                // the table keeps the keyboard
            box.setContentHuggingPriority(.required, for: .horizontal)         // its own width, never a share of the cell's
            box.setContentCompressionResistancePriority(.required, for: .horizontal)
            box.translatesAutoresizingMaskIntoConstraints = false
            addSubview(box)
            NSLayoutConstraint.activate([
                box.leadingAnchor.constraint(equalTo: leadingAnchor),
                box.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            leading = box.trailingAnchor
        }

        let content: NSView
        switch kind {
        case .text:
            let field = label!
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField = field
            content = field
        case .view:
            let hosting = NSHostingView(rootView: OutlineHostedRoot(content: AnyView(EmptyView()),
                                                                    environment: EnvironmentValues(), isEnabled: true))
            // Keeps the height automatic row heights need and drops the minimum
            // and maximum constraints, which the documentation says cost performance.
            hosting.sizingOptions = [.intrinsicContentSize]
            hosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            host = hosting
            content = hosting
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leading, constant: box == nil ? 0 : 4),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if kind == .view {
            // a hosted cell is as tall as the row: SwiftUI centres what it draws
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { nil }

    func configureText(_ text: String, color: NSColor, font: NSFont, alignment: NSTextAlignment,
                       isEnabled: Bool, tooltip: String?) {
        guard let label else { return }
        label.stringValue = text
        label.textColor = isEnabled ? color : .disabledControlTextColor      // the system's dimmed text
        label.font = font
        label.alignment = alignment
        label.isEnabled = isEnabled
        toolTip = tooltip
    }

    func configureView(_ content: AnyView, environment: EnvironmentValues, isEnabled: Bool, tooltip: String?) {
        host?.rootView = OutlineHostedRoot(content: content, environment: environment, isEnabled: isEnabled)
        toolTip = tooltip
    }

    /// Shows the tick for this row.
    func configureTick(_ state: OutlineTickState, label: String, controlSize: NSControl.ControlSize) {
        guard let checkbox else { return }
        checkbox.controlSize = controlSize
        switch state {
        case .on: checkbox.state = .on
        case .off: checkbox.state = .off
        case .mixed: checkbox.state = .mixed
        case .unavailable: checkbox.state = .off
        }
        checkbox.isEnabled = state.isAvailable
        OutlineAccessibility.describe(tick: checkbox, label: label, state: state)
    }
}
