import AppKit

/// What VoiceOver needs beyond the outline's own structure (`AXOutline` with
/// rows and columns, disclosure included, comes from AppKit).
@MainActor
enum OutlineAccessibility {

    /// A tick says what it includes; an unavailable one says why.
    static func describe(tick button: NSButton, label: String, state: OutlineTickState) {
        button.setAccessibilityLabel(label)
        if case .unavailable(let reason, _) = state {
            button.setAccessibilityHelp(reason)
            button.toolTip = reason
        } else {
            button.setAccessibilityHelp(nil)
            button.toolTip = nil
        }
    }

    /// A section header reads as its title and summary together.
    static func describe(sectionHeader cell: NSTableCellView, header: OutlineSectionHeader) {
        cell.setAccessibilityElement(true)
        cell.setAccessibilityRole(.staticText)
        cell.setAccessibilityLabel([header.title, header.summary].compactMap { $0 }.joined(separator: ", "))
    }
}
