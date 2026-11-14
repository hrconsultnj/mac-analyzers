import Foundation

/// What Setup's Turn Off shows and says about the Time Machine permission, as plain values so a probe can assert it
/// without a screen and without the administrator prompt. The screen only draws these and calls
/// `TimeMachinePermission.revoke()` from a button the person pressed.
public enum TurnOffPermission {

    /// Which rows the screen offers.
    public struct Rows: Equatable, Sendable {
        /// This account's own rule file exists: a row that removes it, behind the administrator prompt.
        public let removable: Bool
        /// The old shared file from a Terminal install exists and this account's own does not: the command to run
        /// (the app cannot read that file and never removes one it did not write). nil otherwise.
        public let earlierCommand: String?
        /// Nothing to show at all.
        public var isEmpty: Bool { !removable && earlierCommand == nil }

        public init(removable: Bool, earlierCommand: String?) {
            self.removable = removable
            self.earlierCommand = earlierCommand
        }
    }

    /// The rows for `SnapshotRunner`'s example targets (`turnoff:permission`, `turnoff:earlier`, `turnoff:none`), so
    /// each state can be looked at without a file in /etc/sudoers.d, which nothing here ever creates for a test.
    public static func example(_ name: String) -> Rows {
        switch name {
        case "permission": Rows(removable: true, earlierCommand: nil)
        case "earlier": Rows(removable: false, earlierCommand: TimeMachinePermission.uninstallCommand())
        default: Rows(removable: false, earlierCommand: nil)
        }
    }

    /// `ruleFileExists` and `legacyFileExists` are what the disk says, read by the screen and given here so a probe
    /// can try every combination. Root (user ID 0) has no rule of its own to remove.
    public static func rows(uid: UInt32 = getuid(),
                            ruleFileExists: Bool = TimeMachinePermission.ruleFileExists(),
                            legacyFileExists: Bool = TimeMachinePermission.legacyFileExists(),
                            suiteRoot: URL = AnalyzersPaths.suiteRoot) -> Rows {
        let own = uid != 0 && ruleFileExists
        let earlier = !own && legacyFileExists
        return Rows(removable: own, earlierCommand: earlier ? TimeMachinePermission.uninstallCommand(suiteRoot: suiteRoot) : nil)
    }

    /// The sentence the result area adds for what happened to the permission, and whether it is the end of it.
    /// `stillThere` is the disk read AFTER the attempt: a removal that reports success but leaves the file is not
    /// reported as done.
    public static func sentence(after outcome: TimeMachinePermission.Outcome, stillThere: Bool) -> (text: String, complete: Bool) {
        switch outcome {
        case .done where !stillThere:
            return ("The Time Machine permission is removed.", true)
        case .done:
            return ("The prompt was accepted, but the Time Machine permission file is still on this Mac. Remove it from the Time Machine screen.", false)
        case .cancelled:
            return ("The Time Machine permission is still in place, because the password prompt was cancelled. Remove it with Remove Permission… on this screen or on the Time Machine screen.", false)
        case .failed(let why):
            return ("The Time Machine permission could not be removed: \(why)", false)
        }
    }

    /// Added to the "Remove from this Mac" confirmation when there is a permission to remove, so the password prompt
    /// that follows is never a surprise.
    public static let confirmation = "You will be asked for your administrator password to remove the permission to delete Time Machine snapshots."

    /// The one sentence of the permission row: what it is, and that removing it asks for a password.
    public static let explanation = "Lets Mac Analyzers delete Time Machine's local snapshots without asking for a password. Removing it asks for your administrator password."
}
