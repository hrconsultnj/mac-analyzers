import Foundation

/// Exit codes as sentences. "exited 127" tells a user nothing.
public enum ExitExplanation {

    public static func explain(exitCode: Int32, verb: String) -> String {
        switch exitCode {
        case 127: "Couldn't \(verb): the cleaning script wasn't found where the app expects it."
        case 126: "Couldn't \(verb): macOS blocked running the script (permissions)."
        case 78: "Couldn't \(verb): the engine refused to start because a setting is invalid — check your protected-apps list."
        case 2: "Couldn't \(verb): the script rejected the options the app passed."
        default: "Couldn't \(verb) — the script stopped with code \(exitCode)."
        }
    }
}
