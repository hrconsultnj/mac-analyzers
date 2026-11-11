import AnalyzersKit
import Foundation
import UIComponents

/// The cleanup's findings in the shape the shared review table takes, and the kinds of
/// thing it found as tabs. One job: the translation. The screens only draw.
extension CleanupReview {

    /// One row per finding. A program a person may tick has its pid as its key (that is
    /// what the engine's list is made of); everything else is shown with the reason it is
    /// left alone, and can never be ticked.
    /// `changed` are the keys of programs that are no longer the ones reviewed: shown, not tickable.
    func reviewRows(changed: Set<String> = []) -> [ReviewRow] {
        candidates.map { row(for: $0, changed: changed) }
    }

    /// The same findings as a finished run's results: nothing to tick, what became of each as its detail.
    func resultRows() -> [ReviewRow] {
        candidates.map { candidate in
            var row = row(for: candidate, changed: [])
            row.keptReason = nil
            row.detail = [candidate.stateText, candidate.detail].compactMap { $0 }.joined(separator: " · ")
            return row
        }
    }

    static func rowID(_ candidate: CleanupCandidate) -> String { candidate.reviewKey }

    private func row(for candidate: CleanupCandidate, changed: Set<String>) -> ReviewRow {
        let name = candidate.count > 1 ? "\(candidate.name) ×\(candidate.count)" : candidate.name
        let reason: String? = {
            if isTickable(candidate, changed: changed) { return nil }
            if candidate.isSelectable {
                return candidate.isEmpty
                    ? "Uses no memory, so closing it would free nothing."
                    : "It ended, or another program took its process number, since the preview."
            }
            if candidate.state == .willBeAskedToQuit { return "Will be asked to quit because it is on your list." }
            return candidate.reason.isEmpty ? candidate.stateText : candidate.reason
        }()
        return ReviewRow(id: candidate.reviewKey, name: name, detail: candidate.detail, group: candidate.groupName,
                         bytes: candidate.memoryBytes, keptReason: reason)
    }
}

/// A category of findings as a shared tab. The raw value is a category's key, or `other`.
struct CleanupTab: RawRepresentable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ category: CleanupCandidate.Category) { rawValue = category.rawValue }
    static let other = CleanupTab(rawValue: "other")
}

/// The tabs for a review (two to six) and which rows each shows. More than six kinds of thing
/// cannot be shown as tabs, so the smallest are gathered under Other.
struct CleanupTabs {
    let items: [ScopeTabItem<CleanupTab>]
    let rowIDs: [CleanupTab: Set<String>]

    var isEmpty: Bool { items.isEmpty }
    /// A screen with one kind of thing has no tabs.
    var hasTabs: Bool { items.count >= 2 }

    /// How many tabs these rows are spread over.
    func tabsCovered(by ids: [String]) -> Int {
        let wanted = Set(ids)
        return rowIDs.values.filter { !$0.isDisjoint(with: wanted) }.count
    }

    init(_ review: CleanupReview) {
        let totals = review.categories()
        let limit = 6
        // keep the biggest kinds when there are too many; the rest go under Other
        let kept = totals.count > limit
            ? Array(totals.sorted { $0.bytes > $1.bytes }.prefix(limit - 1))
            : totals
        let keptCategories = Set(kept.map(\.category))
        var items: [ScopeTabItem<CleanupTab>] = []
        var ids: [CleanupTab: Set<String>] = [:]
        for total in totals where keptCategories.contains(total.category) {
            let tab = CleanupTab(total.category)
            items.append(ScopeTabItem(value: tab, title: total.category.title, symbol: total.category.symbol, count: total.count))
            ids[tab] = Set(review.candidates.filter { $0.category == total.category }.map(CleanupReview.rowID))
        }
        let rest = totals.filter { !keptCategories.contains($0.category) }
        if !rest.isEmpty {
            items.append(ScopeTabItem(value: .other, title: Names.Cleanup.other, symbol: "ellipsis.circle",
                                      count: rest.reduce(0) { $0 + $1.count }))
            let others = Set(rest.map(\.category))
            ids[.other] = Set(review.candidates.filter { others.contains($0.category) }.map(CleanupReview.rowID))
        }
        self.items = items
        rowIDs = ids
    }
}
