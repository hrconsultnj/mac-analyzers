import AnalyzersKit
import Foundation
import Observation
import os

/// The state of one review: which rows are ticked, and what Apply would send.
///
/// A session belongs to ONE preview (`previewID`): the table refuses to apply
/// unless that is the preview it is given, so a screen must build a new session
/// when its preview changes (see `ReviewTable`). What a person unticks is kept per
/// preview in `ReviewTickStore`, so it survives leaving the screen and coming back.
/// The rules themselves live in `ReviewSelection` (AnalyzersKit), where a probe
/// proves them.
@MainActor @Observable
final class ReviewSession {
    private(set) var rows: [ReviewRow]
    /// Changes whenever the rows do (a row stopped being choosable): the table redraws on it.
    private(set) var revision = 0
    private(set) var selection: ReviewSelection
    @ObservationIgnored private let ticks: ReviewTickStore

    var previewID: UUID { selection.previewID }

    init(previewID: UUID, rows: [ReviewRow], ticks: ReviewTickStore = .shared) {
        var seen = Set<String>()
        let unique = rows.filter { seen.insert($0.id).inserted }
        if unique.count != rows.count {
            // keep the first of each key and say so; a debug build must not stop for it
            Logger(subsystem: "com.mac-analyzers.app", category: "review")
                .error("a review was given \(rows.count - unique.count) repeated key(s); the first of each is kept")
        }
        let shown = unique.map(Self.withUnlistableKept)
        self.rows = shown
        self.ticks = ticks
        selection = ReviewSelection(
            previewID: previewID,
            items: shown.map { ReviewSelection.Item(id: $0.id, choosable: $0.keptReason == nil, acts: $0.acts) },
            deselected: ticks.deselected(for: previewID),
            // rows of nothing are folded out of sight: nobody approves what they cannot see
            startsUnticked: shown.contains { $0.bytes != nil } ? Set(shown.filter { $0.bytes == 0 }.map(\.id)) : [])
    }

    /// A row whose key the approved list cannot carry (it has a line break) is shown as kept, with
    /// the reason in words: decided here so no screen has to remember it, and the selection, the bar's
    /// counts, the sent list and the confirmation all see the same row as not choosable.
    private static func withUnlistableKept(_ row: ReviewRow) -> ReviewRow {
        guard !row.acts, !ApprovedSet.isListable(row.id) else { return row }
        var kept = row
        kept.keptReason = ApprovedSet.unlistableReason
        return kept
    }

    /// A review that is only read: no preview behind it, nothing to tick.
    convenience init(readOnly rows: [ReviewRow]) {
        self.init(previewID: UUID(), rows: rows, ticks: ReviewTickStore())
    }

    func isTicked(_ id: String) -> Bool { selection.isTicked(id) }
    /// Whether anything is ticked, without building the rows (Select None's enabled state).
    var hasTicked: Bool { selection.hasTicked }

    func setTicked(_ id: String, _ ticked: Bool) {
        selection.setTicked(id, ticked)
        ticks.save(selection.deselected, for: previewID)
    }

    /// Many keys at once (a group's tick): one save, not one per key.
    func setTicked(_ ids: [String], _ ticked: Bool) {
        for id in ids { selection.setTicked(id, ticked) }
        ticks.save(selection.deselected, for: previewID)
    }

    func selectAll() { selection.selectAll(); ticks.save(selection.deselected, for: previewID) }
    var isAllSelected: Bool { selection.isAllSelected }

    func selectNone() { selection.selectNone(); ticks.save(selection.deselected, for: previewID) }

    /// Forgets the ticks: the preview was applied (or discarded).
    func dropTicks() { ticks.drop(previewID) }

    private var rowsByID: [String: ReviewRow] { Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) }) }

    /// The ticked rows; a row that cannot be chosen is never among them.
    var selectedRows: [ReviewRow] {
        let byID = rowsByID
        return selection.tickedIDs.compactMap { byID[$0] }
    }
    var selectedBytes: Int64 { selectedRows.compactMap(\.bytes).reduce(0, +) }
    var hasSizes: Bool { rows.contains { $0.bytes != nil } }
    var choosableCount: Int { selection.choosableCount }
    /// Rows the cleanup leaves alone (acting rows are not among them).
    var keptCount: Int { rows.filter { $0.keptReason != nil }.count }
    var actingRows: [ReviewRow] { rows.filter(\.acts) }

    /// A screen changes which rows can be chosen IN PLACE (a program ended while the review is
    /// open) without building a new session: ticks on rows that stay choosable are untouched, a
    /// row that stops being choosable is unticked and gets the reason; `nil` makes it choosable.
    func updateChoosable(_ changes: [(id: String, keptReason: String?)]) {
        let byID = Dictionary(changes.map { ($0.id, $0.keptReason) }, uniquingKeysWith: { first, _ in first })
        var now: [String: Bool] = [:]
        let newRows = rows.map { row -> ReviewRow in
            guard !row.acts, let reason = byID[row.id] else { return row }
            var changed = row
            changed.keptReason = reason
            changed = Self.withUnlistableKept(changed)       // a screen cannot make such a row choosable
            now[row.id] = changed.keptReason == nil
            return changed
        }
        let selectionChanged = selection.updateChoosable(now)
        // only a real change regroups the table: a screen may call this on every refresh
        guard selectionChanged || newRows != rows else { return }
        rows = newRows
        ticks.save(selection.deselected, for: previewID)
        revision += 1
    }

    /// "12 selected · 3.2 GB" (and "· 3 kept" when some rows are left alone).
    var summary: String {
        var text = "\(selectedRows.count) selected"
        if hasSizes { text += " · \(ByteSize.format(selectedBytes))" }
        if keptCount > 0 { text += " · \(keptCount) kept" }
        return text
    }

    /// "312 items · 23.4 GB", for a review that is only read.
    var readOnlySummary: String {
        let noun = rows.count == 1 ? "item" : "items"
        guard hasSizes else { return "\(rows.count) \(noun)" }
        return "\(rows.count) \(noun) · \(ByteSize.format(rows.compactMap(\.bytes).reduce(0, +)))"
    }

    /// What Apply sends to the kernel.
    var approved: ApprovedSet { selection.approved }
}
