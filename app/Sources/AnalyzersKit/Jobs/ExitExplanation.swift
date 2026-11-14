import Foundation

/// Exit codes as sentences. "exited 127" tells a user nothing.
public enum ExitExplanation {

    public static func explain(exitCode: Int32, verb: String) -> String {
        switch exitCode {
        case 127: "Couldn't \(verb): the cleaning script wasn't found where the app expects it."
        case 126: "Couldn't \(verb): macOS blocked running the script (permissions)."
        // 78: a script refused to start because of a setting. Which setting
        // differs by script (the protected-apps list, the list of build-cache
        // folder names), so the sentence points at the run's own output.
        case 78: "Couldn't \(verb): it refused to start because one of its settings isn't valid. The run's output says which one."
        // 79: a part of the engine the script needs in order to run safely is
        // missing from the installation — not something a setting can fix.
        case 79: "Couldn't \(verb): a part of Mac Analyzers is missing, so it refused to run rather than run without its safety checks. Update or reinstall Mac Analyzers to repair it."
        case 2: "Couldn't \(verb): the script rejected the options the app passed."
        default: "Couldn't \(verb) — the script stopped with code \(exitCode)."
        }
    }
}
