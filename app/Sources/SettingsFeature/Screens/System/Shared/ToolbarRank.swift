import SwiftUI

/// How much a toolbar item matters on its screen. The system moves the low
/// ones into its overflow menu first when the window narrows, so what a person
/// clicks most stays visible. `visibilityPriority` arrived in macOS 26.1; on
/// 26.0 every item keeps the system's own order, which is the same behaviour
/// without a stated rank.
enum ToolbarRank {
    case high, low
}

extension ToolbarContent {
    @ToolbarContentBuilder func rank(_ rank: ToolbarRank) -> some ToolbarContent {
        if #available(macOS 26.1, *) {
            visibilityPriority(rank == .high ? .high : .low)
        } else {
            self
        }
    }
}
