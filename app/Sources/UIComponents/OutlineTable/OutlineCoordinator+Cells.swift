import AppKit
import SwiftUI

extension OutlineCoordinator {

    /// The control size AppKit's controls and fonts follow, from the environment.
    var controlSize: NSControl.ControlSize {
        switch environment.controlSize {
        case .mini: .mini
        case .small: .small
        case .large: .large
        case .extraLarge: .extraLarge
        default: .regular
        }
    }

    /// The tick to draw for a row: the caller's state, except that what the
    /// person just clicked shows until the caller has heard about it.
    func effectiveTick(for node: Node) -> OutlineTickState? {
        guard let ticks = configuration.ticks else { return nil }
        let state = ticks.state(node.row)
        if state.isAvailable, let pending = pending.tickValues[node.id] { return pending ? .on : .off }
        return state
    }

    func cell(for node: Node, column: NSTableColumn, definition: OutlineColumn<Row>) -> NSView {
        let hasTick = column === outline.outlineTableColumn && configuration.ticks != nil
        let kind: OutlineCell.Kind
        switch definition.cell {
        case .text: kind = .text
        case .view: kind = .view
        }
        let identifier = OutlineCell.identifier(column: definition.id, kind: kind, hasTick: hasTick)
        let cell = (outline.makeView(withIdentifier: identifier, owner: self) as? OutlineCell)
            ?? OutlineCell(identifier: identifier, kind: kind, hasTick: hasTick,
                           target: self, action: #selector(tickClicked(_:)))
        configure(cell, for: node, definition: definition)
        return cell
    }

    /// Puts a row's current values into a cell: a new one, a reused one, or one
    /// already on screen (a values refresh does not go back through AppKit).
    func configure(_ cell: OutlineCell, for node: Node, definition: OutlineColumn<Row>) {
        let isEnabled = configuration.rowEnabled?(node.row) ?? true
        let tooltip = definition.tooltip?(node.row)
        switch definition.cell {
        case .text(let text):
            let size = NSFont.systemFontSize(for: controlSize)
            let font = definition.usesMonospacedDigits
                ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
                : NSFont.systemFont(ofSize: size)
            cell.configureText(text(node.row),
                               color: Self.color(for: definition.style?(node.row) ?? .primary),
                               font: font,
                               alignment: definition.horizontalAlignment == .trailing ? .right : .left,
                               isEnabled: isEnabled, tooltip: tooltip)
        case .view(let make):
            // a SwiftUI view in a cell centres itself in the width it is given: the column's
            // alignment decides where it sits, which is the job here, not a size
            let alignment: Alignment = definition.horizontalAlignment == .trailing ? .trailing : .leading
            let content = AnyView(make(node.row).frame(maxWidth: .infinity, alignment: alignment))
            cell.configureView(content, environment: environment, isEnabled: isEnabled, tooltip: tooltip)
        }
        if cell.checkbox != nil, let ticks = configuration.ticks, let state = effectiveTick(for: node) {
            cell.configureTick(state, label: ticks.label(node.row), controlSize: controlSize)
        }
    }

    static func color(for style: OutlineTextStyle) -> NSColor {
        switch style {
        case .primary: .labelColor
        case .secondary: .secondaryLabelColor
        case .tertiary: .tertiaryLabelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }
}
