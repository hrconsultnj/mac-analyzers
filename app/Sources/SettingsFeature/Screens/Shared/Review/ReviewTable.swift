import AnalyzersKit
import SwiftUI

/// What the confirmation before an apply says. The title is built from the bar's own
/// numbers ("Move 9 Items (8.5 GB) to the Trash?"); a permanent delete adds a second
/// question that must also be answered before anything runs.
struct ReviewConfirmation {
    /// "Move", "Delete", "Close": the verb of the title.
    var verb: String
    /// What follows the count: "to the Trash", "permanently".
    var destination: String
    /// The sentence under the title.
    var message: String
    /// A second sentence for a delete that cannot be undone; nil when the first is enough.
    var permanent: String?
    /// When set ("Apps to remove"), the dialog's message also names what is ticked, each group once ("Apps to
    /// remove: A, B, and C."): for a review whose rows a person should see by name before agreeing.
    var namesRows: String?
}

/// The review before a cleanup, as a table: a tick per row, rows grouped under the
/// project or app they belong to (one parent row with its count and total, opening
/// to its members; empty ones fold into one closed row), sortable columns,
/// "12 selected · 3.2 GB" and one Apply. The apply goes through
/// `JobStore.apply(from:approved:)` and nothing else, so the kernel's rules (a preview
/// older than the review window, a discarded one, or one that never found its own
/// results cannot be applied) hold on every screen that uses this.
///
/// A session belongs to one preview. Build it again whenever the preview changes, or
/// Apply stays disabled with "These rows are from an older preview":
///
///     @State private var session: ReviewSession?
///
///     ReviewTable(session: session, preview: preview, applyTitle: "Move to Trash",
///                 confirmation: ReviewConfirmation(verb: "Move", destination: "to the Trash",
///                                                  message: "You can put them back from Undo."),
///                 onPreviewAgain: { runPreview() }, onApplied: { adopt($0) })
///         .task(id: preview.id) {
///             session = ReviewSession(previewID: preview.id, rows: found.map {
///                 ReviewRow(id: $0.path, name: $0.title, detail: $0.path, group: $0.project,
///                           bytes: $0.bytes, iconPath: $0.path,
///                           keptReason: $0.isActive ? "Kept: the project is active" : nil)
///             })
///         }
///
/// `preview` is the finished preview job the rows came from; without one Apply stays
/// dimmed. Rows that carry a `keptReason` are shown, with the reason, but cannot be
/// ticked and never count. A review that is only read (a finished run's results) passes
/// `readOnly: true` and a `ReviewSession(readOnly:)`: no ticks, no Apply. Put the table
/// inside a `DataScreen`; the title and subtitle belong to the screen.
struct ReviewTable: View {
    @Bindable var session: ReviewSession
    var preview: Job?
    var applyTitle = "Apply"
    var confirmation: ReviewConfirmation?
    var readOnly = false
    /// A line under the summary of a read-only review ("and 114 smaller ones are in the raw output").
    var note: String?
    /// Shown beside a disabled Apply when the review is old or from another preview.
    var onPreviewAgain: (() -> Void)?
    var onApplied: (Job) -> Void = { _ in }
    /// Shows only these rows (a category's tab); the bar, Select All and Apply still cover the
    /// whole review. nil shows every row.
    var only: Set<String>?
    /// What Apply sends, when the screen has a stricter rule than the ticks: a cleanup that
    /// leaves out a process whose pid is no longer the program that was reviewed. nil sends the
    /// ticks. Whatever it returns, rows with a `keptReason`, rows left unticked (the fold's
    /// included) and keys the review never listed are removed before anything is sent, and the
    /// bar's and the confirmation's counts are the rows that ARE sent.
    var approval: ((ReviewSession) -> ApprovedSet)?
    /// The ids of each tab's rows, so the bar can say how many tabs the selection spans. Without
    /// it the bar says how many selected rows are in other tabs.
    var tabs: [Set<String>] = []
    /// The words for rows the apply acts on without a tick here ("2 apps will quit", "and Quit
    /// Opera, Docker"); nil when the review has none.
    var alsoActs: ReviewAlsoActs?
    /// The first column's title and the value column's, for a review that is not files with sizes
    /// (a run's events: "What Happened", "When").
    var nameTitle: String = Names.Column.name
    var valueTitle: String?
    /// The names the confirmation gives for the rows the apply acts on, when the screen knows them
    /// from what is SENT (the Memory track's list of apps); without it the session's acting rows.
    var actingNames: ((ReviewSession) -> [String])?
    /// Names the screen for what the table remembers of it (which groups are open, column widths).
    /// A table with a preview may leave it out (the key is the preview's kind); a read-only review or
    /// an example has no preview and MUST pass one, or every such table would share one memory.
    var screen: String?
    /// Items a screen offers on a row (right-click, and the selection): `.files` for Show in Finder and
    /// Copy Path. Never changes a tick.
    var rowMenu: ReviewRowMenu?

    @Environment(JobStore.self) private var store
    /// nil until a person sorts: then what this screen last had (`ReviewSortMemory`), so replacing the table keeps it.
    @State private var chosenSort: [KeyPathComparator<ReviewNode>]?
    private var sortOrder: Binding<[KeyPathComparator<ReviewNode>]> {
        Binding(get: { chosenSort ?? ReviewSortMemory.order(for: screenKey) },
                set: { chosenSort = $0; ReviewSortMemory.save($0, for: screenKey) })
    }
    @State private var tree = ReviewTreeCache()
    @State private var expansions = ReviewExpansions()
    @State private var asking = false
    @State private var askingPermanent = false
    @State private var appliedFor = PerPreview<Job>()
    @State private var expired = false
    /// What was on offer when the confirmation opened: Apply sends exactly this.
    @State private var frozen: ReviewFrozen?
    @State private var notice: String?

    /// The apply started for THIS preview; one started for an earlier preview does not count.
    private var applied: Job? { appliedFor.value(for: preview?.id) }

    private var gate: ReviewApplyGate {
        if expired { return .expired }
        return session.selection.gate(previewID: preview?.id, finishedAt: preview?.finishedAt)
    }

    /// Why Apply is not available, or what its last try said: in words, in the bar.
    private var message: String? {
        if let notice { return notice }
        if let applied {
            switch applied.state {
            case .queued, .running: return "Applying…"
            case .succeeded: return "Applied. Preview again to review what is left."
            case .failed(let failure): return failure.message
            case .cancelled: return "Stopped."
            }
        }
        return gate.sentence
    }

    private func applyDisabled(_ offer: Offer) -> Bool {
        if gate != .ready || !ReviewWording.hasWork(sent: offer.rows.count, acting: offer.acting.count) { return true }
        guard let applied else { return false }
        switch applied.state {
        case .queued, .running, .succeeded: return true
        case .failed, .cancelled: return false
        }
    }

    /// What the table remembers per screen.
    private var screenKey: String {
        assert(screen != nil || preview != nil,
               "A ReviewTable with no preview (a read-only review, an example) must be given `screen:`; without it every such table would share one memory of which groups are open.")
        return "review.\(screen ?? preview?.kind.rawValue ?? "unnamed")"
    }

    var body: some View {
        // what is on offer is worked out ONCE per body (a pass over every row, a few ms at Downloads'
        // size) and read by the bar and the change watcher; actions work it out again at the moment they act
        let offer = readOnly ? nil : offer()
        return ReviewTableBody(nodes: tree.nodes(for: session, order: sortOrder.wrappedValue, only: only), sortOrder: sortOrder,
                        session: readOnly ? nil : session, expansion: expansions.expansion(for: screenKey),
                        screen: screenKey, nameTitle: nameTitle, valueTitle: valueTitle, rowMenu: rowMenu,
                        rowsFor: { ids in session.rows.filter { ids.contains($0.id) } })
            .safeAreaInset(edge: .bottom, spacing: 0) { bar(offer) }
            .confirmationDialog(frozen?.title ?? applyTitle, isPresented: $asking, titleVisibility: .visible) {
                Button(applyTitle, role: .destructive) { chosen() }
            } message: {
                // the full list of what else will happen stays readable here, however long
                Text([confirmation?.message, frozen?.actingLine].compactMap { $0 }.joined(separator: " "))
            }
            .confirmationDialog("Delete Permanently?", isPresented: $askingPermanent, titleVisibility: .visible) {
                Button("Delete Permanently", role: .destructive) { apply() }
            } message: {
                Text(permanentMessage())
            }
            // The list changed while the dialog was open: close it and say why. Limit: this runs when the
            // view's body is evaluated, i.e. when observed state or the parent changes; a rule that
            // reads state nothing observes is noticed at the next redraw (and Apply itself always
            // sends the frozen set, so the dialog can never send something other than it showed).
            .onChange(of: offer?.approved) { _, live in
                guard let frozen, let live, asking || askingPermanent, !frozen.holds(for: live) else { return }
                asking = false
                askingPermanent = false
                self.frozen = nil
                notice = "What would be applied changed while you were confirming. Check the list and press Apply again."
            }
            .task(id: preview?.id) { await watchExpiry() }
            .task(id: applied?.id) { await watchApplied() }
    }

    // MARK: - the bar

    @ViewBuilder private func bar(_ offer: Offer?) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(offer.map(summaryText) ?? session.readOnlySummary).monospacedDigit()
                if let line = readOnly ? note : message {
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !readOnly {
                if let onPreviewAgain, gate == .expired || gate == .differentPreview {
                    Button(Names.Review.previewAgain, action: onPreviewAgain)
                }
                Button(Names.Review.selectAll) { session.selectAll() }
                    .disabled(session.isAllSelected)
                Button(Names.Review.selectNone) { session.selectNone() }
                    .disabled(!session.hasTicked)
                Button(applyTitle) { confirmation == nil ? apply() : openConfirmation() }
                    .buttonStyle(.glassProminent)
                    .disabled(offer.map(applyDisabled) ?? true)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - applying

    /// What Apply would send and what the bar says about it, from ONE pass over the rows.
    private struct Offer {
        let approved: ApprovedSet
        let rows: [ReviewRow]
        let bytes: Int64
        let acting: [ReviewRow]
        let keptCount: Int
        let hasSizes: Bool

        var countText: String { ReviewWording.countText(count: rows.count, bytes: hasSizes ? bytes : nil) }
    }

    /// What Apply would send: the caller's `approval` (or the ticks), narrowed to ticked, choosable
    /// rows. Applying, the bar and the confirmation all read this one set.
    private func offer() -> Offer {
        let wanted = approval?(session) ?? session.approved
        // a rule that returns keys the review never listed is a bug in the screen: say so in a debug build
        assert(wanted.isUnrestricted || Set(wanted.approved).isSubset(of: Set(session.selection.items.map(\.id))),
               "an approval rule returned keys that are not in the review")
        let approved = session.selection.narrowed(wanted)
        let ids = Set(approved.approved)
        let rows = session.rows.filter { ids.contains($0.id) }
        return Offer(approved: approved, rows: rows, bytes: rows.compactMap(\.bytes).reduce(0, +),
                     acting: session.actingRows, keptCount: session.keptCount, hasSizes: session.hasSizes)
    }

    private var sent: ApprovedSet { offer().approved }

    /// The second question of a permanent delete: how many, and the sentence the screen gave.
    private func permanentMessage() -> String {
        let count = frozen?.countText ?? offer().countText
        return "\(count). \(confirmation?.permanent ?? "")"
    }

    /// "12 selected across 3 tabs · 2 apps will quit · 3.2 GB · 1 kept", from the rows that are sent.
    private func summaryText(_ offer: Offer) -> String {
        let rows = offer.rows
        var outside = 0
        var spanned = 0
        if let only {
            outside = rows.filter { !only.contains($0.id) }.count
            spanned = tabs.filter { tab in rows.contains { tab.contains($0.id) } }.count
        }
        return ReviewWording.summary(selected: rows.count, bytes: offer.hasSizes ? offer.bytes : nil,
                                     outside: outside, tabsSpanned: spanned,
                                     acting: offer.acting.count, alsoActs: alsoActs, kept: offer.keptCount)
    }

    /// What the dialog calls the ticked rows: their group's name when they have one (an app, whose files are rows
    /// of their own), else the row's own name; each once, in review order.
    private static func namesOfWhatIsAsked(_ rows: [ReviewRow]) -> [String] {
        var seen: [String] = []
        for row in rows { let name = row.group ?? row.name; if !seen.contains(name) { seen.append(name) } }
        return seen
    }

    /// Opens the confirmation with the set that is on offer NOW; Apply sends exactly that.
    private func openConfirmation() {
        notice = nil
        guard let confirmation else { return }
        let now = offer()
        // the names are read once, here: the title and the message line are frozen with the set
        let names = actingNames?(session) ?? now.acting.map(\.name)
        frozen = ReviewFrozen(
            sent: now.approved,
            title: ReviewWording.confirmationTitle(
                verb: confirmation.verb, destination: confirmation.destination, count: now.rows.count,
                bytes: now.hasSizes ? now.bytes : nil, alsoActs: alsoActs, actingNames: names),
            countText: now.countText,
            actingLine: alsoActs.flatMap { ReviewWording.fullActingLine(alsoActs: $0, names: names) }
                ?? confirmation.namesRows.map { "\($0): \(ReviewWording.fullNames(Self.namesOfWhatIsAsked(now.rows)))." })
        asking = true
    }

    private func chosen() {
        if confirmation?.permanent != nil { askingPermanent = true } else { apply() }
    }

    private func apply() {
        guard let preview else { return }
        guard gate == .ready else {
            // say why instead of closing the dialog without a word
            frozen = nil
            notice = gate.sentence ?? "This review can no longer be applied. Preview again."
            return
        }
        // from a confirmation: exactly what it showed; without one: the set as it is now
        let job = store.apply(from: preview, approved: frozen?.sent ?? sent)
        frozen = nil
        appliedFor.set(job, for: preview.id)
        onApplied(job)
    }

    /// Apply turns itself off, saying "Preview Again", the moment the review window passes.
    private func watchExpiry() async {
        expired = false
        // ticks of previews that can no longer be applied are of no use
        let live = store.jobs.filter { $0.intent == .preview && !store.dismissed.contains($0.id) }.map(\.id)
        ReviewTickStore.shared.keepOnly(Set(live))
        guard let finished = preview?.finishedAt else { return }
        let wait = finished.addingTimeInterval(JobStore.reviewWindow).timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        if !Task.isCancelled { expired = true }
    }

    /// Once the apply has finished successfully the ticks are of no further use.
    private func watchApplied() async {
        guard let job = applied else { return }
        while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(200)) }
        if case .succeeded = job.state { session.dropTicks() }
    }
}

/// The grouped, sorted tree, rebuilt when the session (a different review), the sort or the
/// rows in view change, never on a tick: a tick must not regroup thousands of rows.
@MainActor
final class ReviewTreeCache {
    private let memo = IdentityMemo<ReviewSession, Key, [ReviewNode]>()

    func nodes(for session: ReviewSession, order: [KeyPathComparator<ReviewNode>], only: Set<String>? = nil) -> [ReviewNode] {
        memo.value(for: session, key: Key(order: order, only: only, revision: session.revision)) {
            ReviewNode.tree(only.map { keep in session.rows.filter { keep.contains($0.id) } } ?? session.rows, order: order)
        }
    }

    private struct Key: Equatable {
        let order: [KeyPathComparator<ReviewNode>]
        let only: Set<String>?
        let revision: Int
    }
}
