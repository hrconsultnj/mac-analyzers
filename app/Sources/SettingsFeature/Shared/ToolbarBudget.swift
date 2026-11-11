import AppKit
import SwiftUI

/// How much room a window's toolbar has for a screen's own controls, worked out from what is known:
/// the width of the screen's column, the title block, and whether the shell's job status item is
/// showing. The system decides what goes into the overflow menu, but it cannot collapse the tabs
/// into one control, so the tabs ask here whether the full row fits (`ScopeTabs` toolbar modifier).
///
/// Calibrated from renders: at a 690 pt column (a 900 pt window) the nav buttons, a title block of
/// about 125 pt, four tabs of 380 pt and the search icon fit; with 422 pt tabs they did not.
enum ToolbarBudget {
    /// Back and Forward, the search button and the toolbar's own margins.
    static let chrome: CGFloat = 177
    /// The job status item with its Stop button, when it shows.
    static let statusItem: CGFloat = 270
    static let defaultTitleWidth: CGFloat = 130

    /// The width of the toolbar's title block: the wider of the title and its subtitle, set the way
    /// the toolbar sets them.
    static func titleWidth(title: String, subtitle: String?) -> CGFloat {
        let t = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).size().width
        let s = subtitle.map { NSAttributedString(string: $0, attributes: [.font: NSFont.systemFont(ofSize: 11)]).size().width } ?? 0
        return ceil(max(t, s))
    }
}

/// Published by `DataScreen`: how wide its title block is.
struct ToolbarTitleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

/// Published by a screen with tabs: whether its toolbar has room for the shell's job status item
/// beside the tabs. The shell hides the item when the answer is no, so the item gives way before
/// the tabs do. No tabs on screen: no answer, and the item shows.
struct ToolbarAllowsStatusKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value && nextValue() }
}
