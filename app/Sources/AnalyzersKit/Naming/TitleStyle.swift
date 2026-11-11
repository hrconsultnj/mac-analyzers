import Foundation

/// Title-style capitalization as Apple's style guide states it, as a check
/// rather than a formatter: it says which words of a name are written wrong,
/// never what the name should be. The exception lists live here and nowhere
/// else.
///
/// The rules it applies (Apple Style Guide, "capitalization"):
/// - the first and the last word are capitalized, whatever they are;
/// - articles, coordinating conjunctions, `to` and short prepositions stay
///   lowercase in the middle of a name;
/// - every other word is capitalized, and so is the second half of a
///   hyphenated word (except `Built-in` and `Plug-in`);
/// - words that always begin lowercase (`macOS`) and acronyms (`CPU`) keep
///   their form.
///
/// A preposition that is part of a phrasal verb (`Turn On`, `Log In`) is
/// capitalized, so `in`, `on`, `off`, `up` and `out` are allowed either way:
/// the check cannot tell a verb from a preposition, and a check that cries
/// wolf gets ignored.
public enum TitleStyle {

    /// Lowercase in the middle of a name.
    public static let smallWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "for", "yet", "so", "as", "to",
        "of", "at", "by", "with", "from", "per", "via", "into", "onto", "over", "upon", "than",
    ]

    /// Allowed in either case in the middle of a name (phrasal verbs).
    public static let particles: Set<String> = ["in", "on", "off", "up", "out"]

    /// Begin lowercase wherever they appear.
    public static let alwaysLowercaseStart: Set<String> = [
        "macOS", "iOS", "iPadOS", "iPhone", "iPad", "iCloud", "iMac", "iTunes", "watchOS", "tvOS",
        "visionOS",
    ]

    /// Hyphenated words whose second half stays lowercase (plurals included).
    public static let lowercaseCompounds: Set<String> = ["Built-in", "Plug-in"]

    /// Written in capitals on purpose. Any other word of two or more letters
    /// in capitals is a label shouting, which is what this check exists to stop.
    public static let acronyms: Set<String> = [
        "CPU", "GPU", "RAM", "PID", "KB", "MB", "GB", "TB", "I/O", "IO", "AI", "MCP", "UI", "ID",
        "URL", "VPN", "SSH", "DMG", "OS", "USB", "SSD", "API", "VM", "PDF", "TM", "OK",
    ]

    /// The words of `name` that break the rules, with the reason. Empty when
    /// the name is written correctly.
    public static func violations(in name: String) -> [String] {
        let words = name.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var found: [String] = []
        for (index, word) in words.enumerated() {
            let edge = index == 0 || index == words.count - 1
            // symbols, numbers and separators carry no case
            guard let first = word.unicodeScalars.first(where: { CharacterSet.letters.contains($0) }) else { continue }
            let core = word.trimmingCharacters(in: CharacterSet.letters.inverted)
            if alwaysLowercaseStart.contains(core) && !edge { continue }
            if acronyms.contains(core) { continue }
            // a whole word in capitals that is not an acronym
            let letters = core.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            if letters.count >= 2, core == core.uppercased(), core != core.lowercased() {
                found.append("\"\(core)\" is written in capitals and is not a known acronym")
                continue
            }
            // Built-in, Plug-in and their plurals: the second half stays lowercase
            if let compound = lowercaseCompounds.first(where: { core.lowercased().hasPrefix($0.lowercased()) }) {
                let expectedTail = compound.split(separator: "-").dropFirst().joined(separator: "-")
                let tail = core.split(separator: "-").dropFirst().joined(separator: "-")
                if !tail.hasPrefix(expectedTail) {
                    found.append("\"\(core)\" is written \"\(compound)\" (second half lowercase)")
                }
                continue
            }
            // a/b: each side is a word of its own
            if core.contains("/") {
                for part in core.split(separator: "/") where !part.isEmpty {
                    if let lead = part.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(lead),
                       !alwaysLowercaseStart.contains(String(part)), !smallWords.contains(part.lowercased()) {
                        found.append("\"\(part)\" in \"\(core)\" should be capitalized")
                    }
                }
                continue
            }
            if core.contains("-") {
                let parts = core.split(separator: "-").filter { !$0.isEmpty }
                for (position, part) in parts.enumerated() {
                    let inner = position > 0 && position < parts.count - 1
                    if inner && smallWords.contains(part.lowercased()) { continue }   // Up-to-Date
                    if let lead = part.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(lead),
                       !alwaysLowercaseStart.contains(String(part)) {
                        found.append("\"\(part)\" in \"\(core)\" should be capitalized")
                    }
                }
                continue
            }
            let lowercase = CharacterSet.lowercaseLetters.contains(first)
            let lower = core.lowercased()
            if edge {
                if lowercase && !alwaysLowercaseStart.contains(core) {
                    found.append("\"\(core)\" starts or ends the name, so it should be capitalized")
                }
            } else if smallWords.contains(lower) {
                if !lowercase { found.append("\"\(core)\" is a small word and should be lowercase") }
            } else if particles.contains(lower) {
                continue
            } else if lowercase {
                found.append("\"\(core)\" should be capitalized")
            }
        }
        return found
    }
}
