import AnalyzersKit
import Foundation

/// What a person reads for a status token the engine prints in capitals
/// ("NEEDS SUDO", "IDLE OR COMPLETE"). The token stays the identifier — it is
/// what the parsers match and the logs contain — and this is its label: title
/// style, small words lowercase.
///
/// `plain(_:)` is what a screen shows: the one plain-word answer for each typed
/// engine token (`TokenWords`, in `AnalyzersKit/Naming`). `title(_:)` only
/// title-cases a token that has no typed value; reach for it last.
public enum TokenLabel {

    /// "Would Close" for a process the guard would quit, "Moved to Trash" for a
    /// folder the janitor trashed — the word for the token in its own kind of
    /// thing, never the token itself.
    public static func plain(_ status: ReapItem.Status) -> String { status.plainLabel }
    public static func plain(_ status: StoragePathItem.Status) -> String { status.plainLabel }
    public static func plain(_ status: TempItem.Status) -> String { status.plainLabel }
    public static func plain(_ status: TempMount.Status) -> String { status.plainLabel }
    public static func plain(_ status: SpotlightExposureItem.Status) -> String { status.plainLabel }
    public static func plain(_ verdict: SpotlightAuditRun.Verdict) -> String { verdict.plainLabel }
    public static func plain(_ verdict: LoginItemEntry.Verdict) -> String { verdict.plainLabel }

    /// A token read out of a line of text (`DRY RUN`, `KILLED`): its plain word, or
    /// the token in title style when it has none.
    public static func plain(_ token: String) -> String { TokenWords.plain(token) ?? title(token) }

    public static func title(_ token: String) -> String {
        let small = TitleStyle.smallWords.union(["in", "on"])
        let words = token.split(separator: " ").map(String.init)
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if index > 0, index < words.count - 1, small.contains(lower) { return lower }
            return lower.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
        }.joined(separator: " ")
    }
}
