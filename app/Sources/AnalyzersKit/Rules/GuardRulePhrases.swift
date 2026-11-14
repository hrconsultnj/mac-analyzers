import Foundation

/// A rule in words: the sentence on the Memory Guard screen, for a limit and for a step of the ladder. Written from the data,
/// so a rule the person changes reads differently the moment it changes.
extension GuardRule {

    /// What the rule targets, as a noun phrase with its article ("a developer process", "an app").
    var subjectPhrase: String {
        switch selector {
        case "tools.devTooling": return shape.isProcessMeasure ? "a developer process" : "a developer tool"
        case "tools.simulators": return "a simulator or emulator"
        case "tools.databases": return "a database"
        case "tools.other": return "a command"
        case "apps.*": return "an app"
        case "macos.*": return "a macOS process"
        default:
            let name = Names.Kind.name(forID: selector)?.lowercased() ?? selector
            return "a \(name)"
        }
    }

    private var verb: String {
        switch action {
        case .stop: "Stops"
        case .notify: "Tells you about"
        case .propose: "Proposes quitting"
        case .askToQuit: "Asks to quit"
        }
    }

    private static func duration(_ seconds: Int) -> String {
        if seconds % 60 == 0 { let minutes = seconds / 60; return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        return "\(seconds) seconds"
    }

    /// "Stops a developer process that holds more than 6 GB." / "Tells you about a command that holds more than 6 GB for 5 minutes."
    public var summary: String {
        switch shape {
        case .limit(let gb, _, let overFor, _):
            let size = gb == gb.rounded() ? "\(Int(gb)) GB" : String(format: "%.1f GB", gb)
            return "\(verb) \(subjectPhrase) that holds more than \(size)\(overFor > 0 ? " for \(Self.duration(overFor))" : "")."
        case .step: return "\(verb) \(stepWhat)."
        }
    }

    /// What a step picks: "the biggest developer process over 500 MB", "any idle simulator", "an app you put on the list".
    public var stepWhat: String {
        let noun = subjectPhrase.split(separator: " ", maxSplits: 1).last.map(String.init) ?? subjectPhrase
        guard case .step(let which, let mb) = shape else { return noun }
        switch which {
        case .idle: return "any idle \(noun)"
        case .biggest: return "the biggest \(noun)"
        case .biggestOver: return "the biggest \(noun) over \(mb ?? 0) MB"
        case .listed: return "an app you put on the list"
        }
    }

    /// The whole ladder as one sentence.
    public static func ladderSentence(_ steps: [GuardRule]) -> String {
        let parts = steps.map { rule -> String in
            let what = rule.stepWhat
            switch rule.action {
            case .stop: return "stops \(what)"
            case .askToQuit: return "asks \(what.replacingOccurrences(of: "an app you put on the list", with: "the apps you put on the list")) to quit"
            case .propose: return "proposes quitting \(what)"
            case .notify: return "tells you about \(what)"
            }
        }
        guard !parts.isEmpty else { return "Memory Guard has no steps for when memory runs out." }
        return "When memory runs out, Memory Guard works down this list, and does the first thing that has something to pick: "
            + parts.joined(separator: ", then ") + "."
    }
}

extension GuardRule.Shape {
    var isProcessMeasure: Bool { if case .limit(_, .process, _, _) = self { true } else { false } }
}
