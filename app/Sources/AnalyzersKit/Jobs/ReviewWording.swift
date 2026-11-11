import Foundation

/// What a review says about rows its apply will act on although the person does not tick them
/// here (Memory Cleanup's "also quit" apps): the words come from the caller, through `Names`.
public struct ReviewAlsoActs: Sendable, Equatable {
    public let singular: String      // "app"
    public let plural: String        // "apps"
    public let verb: String          // "will quit"  (the bar: "2 apps will quit")
    public let confirmVerb: String   // "Quit"       (the dialog: "... and Quit Opera, Docker?")
    public init(singular: String, plural: String, verb: String, confirmVerb: String) {
        self.singular = singular
        self.plural = plural
        self.verb = verb
        self.confirmVerb = confirmVerb
    }
}

/// The sentences of the review's bar and confirmation, built from the numbers that are SENT,
/// so a probe can prove the bar, the dialog and the apply agree.
public enum ReviewWording {

    /// "9 Items (8.5 GB)", or "9 Items" for rows with no size.
    public static func countText(count: Int, bytes: Int64?) -> String {
        let items = "\(count) \(count == 1 ? "Item" : "Items")"
        return bytes.map { "\(items) (\(ByteSize.format($0)))" } ?? items
    }

    /// "Move 9 Items (8.5 GB) to the Trash?", and with rows that act anyway,
    /// "Close 1 Item (2 GB) now and Quit Opera, Docker?".
    public static func confirmationTitle(verb: String, destination: String, count: Int, bytes: Int64?,
                                         alsoActs: ReviewAlsoActs?, actingNames: [String]) -> String {
        // only apps to quit, nothing ticked: "Quit Opera, Docker?"
        if count == 0, let alsoActs, !actingNames.isEmpty {
            return "\(alsoActs.confirmVerb) \(actingNames.joined(separator: ", "))?"
        }
        var title = "\(verb) \(countText(count: count, bytes: bytes)) \(destination)"
        if let alsoActs, !actingNames.isEmpty {
            title += " and \(alsoActs.confirmVerb) \(actingNames.joined(separator: ", "))"
        }
        return title + "?"
    }

    /// Whether Apply has anything to do: rows that are sent, or rows it acts on by another argument.
    public static func hasWork(sent: Int, acting: Int) -> Bool { sent > 0 || acting > 0 }

    /// "12 selected across 3 tabs · 2 apps will quit · 3.2 GB · 1 kept".
    public static func summary(selected: Int, bytes: Int64?, outside: Int, tabsSpanned: Int,
                               acting: Int, alsoActs: ReviewAlsoActs?, kept: Int) -> String {
        var text = "\(selected) selected"
        if outside > 0 { text += tabsSpanned > 1 ? " across \(tabsSpanned) tabs" : ", \(outside) in other tabs" }
        if let bytes { text += " · \(ByteSize.format(bytes))" }
        if acting > 0, let alsoActs { text += " · \(acting) \(acting == 1 ? alsoActs.singular : alsoActs.plural) \(alsoActs.verb)" }
        if kept > 0 { text += " · \(kept) kept" }
        return text
    }
}

/// What was on offer when a confirmation opened. Apply sends exactly this; if the live set stops
/// matching while the dialog is open, the dialog closes and the bar says why.
public struct ReviewFrozen: Sendable {
    public let sent: ApprovedSet
    public let title: String
    /// "9 Items (8.5 GB)": the count the second question of a permanent delete repeats.
    public let countText: String
    public init(sent: ApprovedSet, title: String, countText: String = "") {
        self.sent = sent
        self.title = title
        self.countText = countText
    }
    public func holds(for live: ApprovedSet) -> Bool { live == sent }
}
