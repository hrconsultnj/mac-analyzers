import Foundation

/// What "Remove" can honestly promise for startup items.
///
/// `login-items-audit.sh --apply` removes every user-level leftover it finds.
/// It only removes fewer when the job carries an approved list
/// (`--only-paths`), which the job kernel passes for the kinds that have an
/// approval flag. Until `.loginItems` has one, a Remove on one row would still
/// remove them all, so the screen must say "all" and list them.
public enum StartupRemoval {

    /// True when the kernel narrows a login-items apply to the approved list.
    public static var canNarrowToSelection: Bool { JobKind.loginItems.removesOnlyApproved }

    /// The items a Remove will take, given what the person chose: just those
    /// when the apply can be narrowed, every removable item when it cannot.
    public static func scope(chosen: [StartupItem], removable: [StartupItem]) -> [StartupItem] {
        canNarrowToSelection ? chosen.filter(\.canRemove) : removable
    }

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
