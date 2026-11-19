import SwiftUI

/// Which toolbar items stay when the window narrows and which go to the system's overflow
/// menu first. A screen marks each action once. (The screen's tabs are not toolbar items:
/// they are a bar under the toolbar, see `scopeTabsToolbar`.)
///
///     ToolbarItem { Button("Audit", systemImage: "checklist") { ... } }.toolbarRank(.primary)   // stays
///     ToolbarItem { Button("Export…", systemImage: "square.and.arrow.up") { ... } }.toolbarRank(.secondary)  // leaves first
///
/// One name for the two ranks a screen's toolbar items have, so every screen ranks the same way.
enum ToolbarRank {
    /// Stays visible as long as the system allows.
    case primary
    /// Moves into the overflow menu before anything primary.
    case secondary
}

extension ToolbarContent {
    @ToolbarContentBuilder func toolbarRank(_ rank: ToolbarRank) -> some ToolbarContent {
        // visibilityPriority is macOS 26.1+; on 26.0 the rank does nothing and the system's own overflow order applies
        if #available(macOS 26.1, *) {
            self.visibilityPriority(rank == .primary ? .high : .low)
        } else {
            self
        }
    }
}
