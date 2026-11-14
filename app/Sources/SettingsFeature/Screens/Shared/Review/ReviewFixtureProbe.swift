import AnalyzersKit
import Observation
import SwiftUI

/// The real review table on the fixture's own rows, for the headless probe that drives it
/// (`scripts/outline-probe.sh review`): it builds scenarios from the fixture rows only (never from a real
/// preview or a real `JobStore`), exposes `report()` and nothing that applies, and changes the session only
/// through the named steps below, which do what the bar's buttons and a screen's refresh do.
///
/// It reads no environment and no file. The caller puts a `JobStore` in the environment of `view`, as the
/// main window does for a screen; the probe drives the table through the outline view's public AppKit surface.
@MainActor @Observable
public final class ReviewFixtureProbe {
    @ObservationIgnored private let session: ReviewSession
    public let readOnly: Bool
    /// Shown by `showOnly` / `showAll`, as a category's tab does.
    private var only: Set<String>?

    /// What the review would send, and say, right now.
    public struct Report: Sendable {
        public let ticked: [String]
        public let approved: [String]
        public let isNarrowed: Bool
        public let summary: String
        /// What the confirmation before an apply would be titled for these ticks.
        public let confirmationTitle: String
        public let kept: [String]
        public let acting: [String]
        public let choosable: Int
    }

    /// The saved state (open groups, column sizes) of this probe's table: one name per process, so a
    /// probe run beside another never reads or clears the other's, and none can reach what a person's
    /// app saved under a screen's own name.
    /// A key with a line break, which an approved list (one key per line) cannot carry.
    public static let unlistableKey = "/p/odd/two\nlines"

    static var screenKey: String { "fixture.\(ProcessInfo.processInfo.processIdentifier)" }

    /// - Parameters:
    ///   - acting: adds a row the apply acts on without a tick ("Will Be Asked to Quit").
    ///   - readOnly: a review that is only read: no ticks.
    ///   - unlistable: adds a row whose key has a line break (the approved list cannot carry it).
    public init(acting: Bool = false, readOnly: Bool = false, unlistable: Bool = false) {
        var rows = Self.rows
        if unlistable {
            rows.append(ReviewRow(id: Self.unlistableKey, name: "two lines", detail: "/p/odd/two\nlines", group: "odd", bytes: 5_000_000, iconPath: "/Applications"))
            rows.append(ReviewRow(id: "/p/odd/plain", name: "plain", detail: "/p/odd/plain", group: "odd", bytes: 7_000_000, iconPath: "/Applications"))
        }
        if acting {
            rows.append(ReviewRow(id: "app:Opera", name: "Opera", detail: "Will Be Asked to Quit", group: "Also closes",
                                  bytes: 300_000_000, actsWord: "Will Be Asked to Quit"))
        }
        self.readOnly = readOnly
        session = readOnly ? ReviewSession(readOnly: rows)
                           : ReviewSession(previewID: UUID(), rows: rows, ticks: ReviewTickStore())
    }

    /// Four groups: three with things to choose (the last of them with an empty row, which the table
    /// folds away), and one the cleanup leaves alone. Every row's tooltip is different, so a probe
    /// can find a row by it.
    static let rows: [ReviewRow] = {
        func row(_ group: String, _ name: String, _ bytes: Int64, kept: String? = nil) -> ReviewRow {
            ReviewRow(id: "/p/\(group)/\(name)", name: name, detail: "/p/\(group)/\(name)", group: group, bytes: bytes,
                      iconPath: "/Applications", keptReason: kept.map { "Kept: \($0)" })
        }
        return [
            row("web-app", "node_modules", 1_840_000_000), row("web-app", ".next", 620_000_000), row("web-app", "dist", 96_000_000),
            row("mobile-app", "DerivedData", 3_100_000_000), row("mobile-app", "Pods", 410_000_000),
            row("engine", ".build", 2_250_000_000), row("engine", "target", 780_000_000), row("engine", "tmp", 0),
            row("active", "node_modules", 900_000_000, kept: "open in an editor"),
            row("active", ".turbo", 12_000_000, kept: "its build is running"),
        ]
    }()

    /// A Downloads-sized review for the cost probe: `count` files in five age bands, each with a path of
    /// its own (fixture rows too, generated).
    public init(downloads count: Int) {
        let bands = ["Today", "This Week", "This Month", "This Year", "Older"]
        let weights = [0.04, 0.1, 0.16, 0.3, 0.4]
        var rows: [ReviewRow] = []
        rows.reserveCapacity(count)
        for index in 0..<count {
            var cumulative = 0.0
            var band = bands.count - 1
            for (position, weight) in weights.enumerated() {
                cumulative += weight
                if Double(index) < cumulative * Double(count) { band = position; break }
            }
            let path = "/Users/example/Downloads/file-\(index).dmg"
            rows.append(ReviewRow(id: path, name: "file-\(index).dmg", detail: path, group: bands[band],
                                  bytes: Int64(1 + (index * 7919) % 900_000_000), iconPath: path))
        }
        readOnly = false
        session = ReviewSession(previewID: UUID(), rows: rows, ticks: ReviewTickStore())
    }

    public var view: AnyView { AnyView(ReviewFixtureProbeView(probe: self)) }

    // MARK: report

    public func report() -> Report {
        let approved = session.approved
        let rows = session.rows.filter { Set(approved.approved).contains($0.id) }
        let bytes = rows.compactMap(\.bytes).reduce(0, +)
        return Report(
            ticked: session.selection.tickedIDs, approved: approved.approved, isNarrowed: approved.isNarrowed,
            summary: session.summary,
            confirmationTitle: ReviewWording.confirmationTitle(
                verb: "Move", destination: "to the Trash", count: rows.count, bytes: session.hasSizes ? bytes : nil,
                alsoActs: nil, actingNames: session.actingRows.map(\.name)),
            kept: session.rows.filter { $0.keptReason != nil }.map(\.id),
            acting: session.actingRows.map(\.id), choosable: session.choosableCount)
    }

    /// What Copy Path puts on a pasteboard of its own (never the person's clipboard): how many items, and
    /// each item's text.
    public func copyPathsProbe(_ keys: [String]) -> (items: Int, texts: [String]) {
        let board = NSPasteboard(name: NSPasteboard.Name("ma-probe-copy-\(ProcessInfo.processInfo.processIdentifier)"))
        ReviewFileItems.copy(keys, to: board)
        let items = board.pasteboardItems ?? []
        let texts = items.compactMap { $0.string(forType: .string) }
        board.releaseGlobally()
        return (items.count, texts)
    }

    // MARK: named scenario steps (what a button or a screen's refresh does, nothing else)

    /// The bar's Select All.
    public func barSelectAll() { session.selectAll() }
    /// The bar's Select None.
    public func barSelectNone() { session.selectNone() }
    /// A program ended while the review is open: this row can no longer be chosen ("In use").
    public func ended(_ key: String) { session.updateChoosable([(key, "In use")]) }
    /// The same row can be chosen again (a screen refreshed and found it free).
    public func choosableAgain(_ key: String) { session.updateChoosable([(key, nil)]) }
    /// A category's tab: only this group's rows are shown; the review still covers everything.
    public func showOnly(group: String) { only = Set(session.rows.filter { $0.group == group }.map(\.id)) }
    /// Back to every row.
    public func showAll() { only = nil }

    fileprivate var sessionForView: ReviewSession { session }
    fileprivate var onlyForView: Set<String>? { only }
}

private struct ReviewFixtureProbeView: View {
    @Bindable var probe: ReviewFixtureProbe

    var body: some View {
        ReviewTable(session: probe.sessionForView, applyTitle: "Move to Trash",
                    confirmation: ReviewConfirmation(verb: "Move", destination: "to the Trash",
                                                     message: "You can put them back from Undo."),
                    readOnly: probe.readOnly, only: probe.onlyForView, screen: ReviewFixtureProbe.screenKey, rowMenu: .files)
    }
}
