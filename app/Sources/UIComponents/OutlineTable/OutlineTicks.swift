import Foundation

/// A tick per row. The caller owns what is ticked; the table draws a checkbox
/// in the first column and reports what the person did.
public struct OutlineTicks<Row: Identifiable> {
    let state: @MainActor (Row) -> OutlineTickState
    let set: @MainActor (Row, Bool) -> Void
    let label: @MainActor (Row) -> String

    /// - Parameters:
    ///   - state: the row's tick. A group's state is the combination of its
    ///     choosable members (`OutlineTickState.combining`).
    ///   - set: called with the value the person chose, at once for a click on a box or the Space key
    ///     (so the person's actions reach the caller in the order they were made).
    ///     For a group row the caller sets every choosable member. Never called
    ///     for a row whose state is `.unavailable`.
    ///   - label: what VoiceOver says, e.g. "Include node_modules".
    public init(state: @escaping @MainActor (Row) -> OutlineTickState,
                set: @escaping @MainActor (Row, Bool) -> Void,
                label: @escaping @MainActor (Row) -> String) {
        self.state = state
        self.set = set
        self.label = label
    }
}

public enum OutlineTickState: Equatable, Sendable {
    case on, off
    /// Only on a group row: some, not all, of its choosable members are ticked.
    case mixed
    /// Drawn disabled, off unless `isOn` (a row the action takes without a tick: dimmed and on);
    /// the reason is the tooltip and the accessibility help.
    case unavailable(reason: String, isOn: Bool = false)

    public var isAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    /// The group rule every review shares: a group's state is computed over its
    /// choosable members only.
    ///
    /// - on: all of them are ticked; off: none are; mixed: some are.
    /// - unavailable: the group has no choosable member, with `reason`.
    public static func combining(_ members: [OutlineTickState], whenNoneChoosable reason: String) -> OutlineTickState {
        let choosable = members.filter(\.isAvailable)
        guard !choosable.isEmpty else { return .unavailable(reason: reason) }
        if choosable.allSatisfy({ $0 == .on }) { return .on }
        if choosable.allSatisfy({ $0 == .off }) { return .off }
        return .mixed
    }

    /// The value a click sets: on when the tick was off or mixed, otherwise off.
    /// `nil` for a tick that cannot be clicked.
    var valueAfterClick: Bool? {
        switch self {
        case .on: false
        case .off, .mixed: true
        case .unavailable: nil
        }
    }
}
