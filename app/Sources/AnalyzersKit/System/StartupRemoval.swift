import Foundation

/// What "Remove" can honestly promise for startup items.
///
/// The audit removes only what an approved list names (`--only-paths`), and the
/// job kernel always sends that list for a kind that takes one (login items do:
/// `JobKind.takesReviewedList`). So a Remove on one row sends that row, "Remove
/// Leftovers" sends every removable item, and the script still re-checks each
/// path against what it finds itself when it runs. A bare `--apply` (every
/// leftover) is only what a person types in a terminal; the app cannot send it.
public enum StartupRemoval {

    /// True when the kernel narrows a login-items apply to the approved list.
    public static var canNarrowToSelection: Bool { JobKind.loginItems.removesOnlyApproved }

    /// The items a Remove on a row will take: the chosen ones that can be
    /// removed (every removable item only if the kernel could not narrow).
    public static func scope(chosen: [StartupItem], removable: [StartupItem]) -> [StartupItem] {
        canNarrowToSelection ? chosen.filter(\.canRemove) : removable
    }

    /// What the toolbar's "Remove Leftovers" takes: every removable item. The
    /// screen calls this, so the probe judges the screen's own rule.
    public static func scopeAll(removable: [StartupItem]) -> [StartupItem] { removable }

    /// The approval for that scope, built the way the kernel expects.
    public static func approval(for scope: [StartupItem], removable: [StartupItem]) -> ApprovedSet {
        let keys = removable.compactMap(\.removalKey)
        let chosen = Set(scope.compactMap(\.removalKey))
        return ApprovedSet(approvable: keys, deselected: Set(keys).subtracting(chosen))
    }
}

extension JobKind {
    /// Whether an apply of this kind carries the approved list to the script.
    var removesOnlyApproved: Bool { takesReviewedList }
}
