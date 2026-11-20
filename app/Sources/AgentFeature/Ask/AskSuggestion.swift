import Foundation
import Observation

/// One thing a scheduled scan found that is worth saying (S5): the panel's
/// proactive agent line. The card PROPOSES — its only action opens Ask, where
/// everything goes through the same review as a typed question. It never
/// applies, and a category the person muted is never raised again.
public struct AskSuggestion: Equatable, Sendable {
    /// What kind of thing was found — the unit of the per-category
    /// "don't suggest" toggle.
    public enum Category: String, Sendable, CaseIterable {
        case downloads, caches, temp, recordings

        /// The words the context menu names ("Don't Suggest Downloads Again").
        public var title: String {
            switch self {
            case .downloads: "Downloads"
            case .caches: "Caches & Builds"
            case .temp: "Temp & Agents"
            case .recordings: "Old Recordings"
            }
        }
    }

    public let category: Category
    /// The one line, in the person's terms ("Found 2.5 GB of old files in Downloads.").
    public let line: String
    /// What the finding adds up to, when the scan measured it.
    public let bytes: Int64?

    public init(category: Category, line: String, bytes: Int64? = nil) {
        self.category = category
        self.line = line
        self.bytes = bytes
    }
}

/// The state behind the panel's proactive card. v1 ships the card and its
/// rules; the caller that FEEDS it — the scheduled scan's result crossing the
/// "worth saying" bar — is Phase 5's wiring (see `record`, the one seam).
///
/// Two rules keep it quiet:
///  - frequency cap: one card at most every `cooldown`, measured from what the
///    person was last SHOWN (a defaults key, so it survives a relaunch);
///  - per-category mute: a category turned off from the card's context menu is
///    stored in defaults and never suggested again.
@MainActor @Observable
public final class AskSuggestionCenter {

    /// The panel reads the shared instance, the way the sidebar's badges read
    /// their group-owned state. (One instance per app; Phase 5 may move it to
    /// the environment alongside the JobStore when it wires the feed.)
    public static let shared = AskSuggestionCenter()

    /// The suggestion waiting to be said, if any.
    private(set) var pending: AskSuggestion?

    static let lastShownKey = "ask.suggestion.lastShownAt"
    static let mutedKey = "ask.suggestion.mutedCategories"
    /// One card at most every six hours.
    public nonisolated static let cooldown: TimeInterval = 6 * 60 * 60

    /// THE FEED SEAM — nothing calls it yet. Phase 5 wires the scheduled
    /// storage scan's result here when it crosses the "worth saying" bar
    /// (a size worth acting on). Refuses a muted category and a suggestion
    /// inside the frequency cap, so a chatty scan cannot nag.
    public func record(_ suggestion: AskSuggestion) {
        guard !isMuted(suggestion.category) else { return }
        if let shown = lastShown, Date().timeIntervalSince(shown) < Self.cooldown { return }
        pending = suggestion
    }

    /// What the panel card should show. Showing it stamps the cap, so call it
    /// once (the card's appear), not from the body.
    @discardableResult
    public func suggestionToShow() -> AskSuggestion? {
        guard let suggestion = pending else { return nil }
        UserDefaults.standard.set(Date(), forKey: Self.lastShownKey)
        return suggestion
    }

    /// The card was dismissed (or acted on): nothing waits any more.
    public func dismiss() {
        pending = nil
    }

    /// The card's context menu: never suggest this category again.
    public func mute(category: AskSuggestion.Category) {
        var muted = mutedCategories
        muted.insert(category.rawValue)
        UserDefaults.standard.set(Array(muted).sorted(), forKey: Self.mutedKey)
        pending = nil
    }

    public func isMuted(_ category: AskSuggestion.Category) -> Bool {
        mutedCategories.contains(category.rawValue)
    }

    private var mutedCategories: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.mutedKey) ?? [])
    }

    private var lastShown: Date? {
        UserDefaults.standard.object(forKey: Self.lastShownKey) as? Date
    }
}
