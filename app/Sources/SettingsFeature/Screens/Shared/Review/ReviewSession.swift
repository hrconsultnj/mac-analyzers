import AnalyzersKit
import Foundation
import Observation

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
    let rows: [ReviewRow]
    private(set) var selection: ReviewSelection
    @ObservationIgnored private let ticks: ReviewTickStore

    var previewID: UUID { selection.previewID }

    init(previewID: UUID, rows: [ReviewRow], ticks: ReviewTickStore = .shared) {
        var seen = Set<String>()
        let unique = rows.filter { seen.insert($0.id).inserted }
        assert(unique.count == rows.count, "a review was given the same key twice")
        self.rows = unique
        self.ticks = ticks
        selection = ReviewSelection(
            previewID: previewID,
            items: unique.map { ReviewSelection.Item(id: $0.id, choosable: $0.isChoosable) },
            deselected: ticks.deselected(for: previewID))
    }

    /// A review that is only read: no preview behind it, nothing to tick.
    convenience init(readOnly rows: [ReviewRow]) {
        self.init(previewID: UUID(), rows: rows, ticks: ReviewTickStore())
    }

    func isTicked(_ id: String) -> Bool { selection.isTicked(id) }

    func setTicked(_ id: String, _ ticked: Bool) {
        selection.setTicked(id, ticked)
        ticks.save(selection.deselected, for: previewID)
    }

    func selectAll() { selection.selectAll(); ticks.save(selection.deselected, for: previewID) }
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
    var keptCount: Int { rows.count - selection.choosableCount }

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
