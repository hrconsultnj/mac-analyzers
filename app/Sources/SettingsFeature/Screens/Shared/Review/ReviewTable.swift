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

    @Environment(JobStore.self) private var store
    @State private var sortOrder = [KeyPathComparator(\ReviewNode.sortBytes, order: .reverse)]
    @State private var tree = ReviewTreeCache()
    @State private var asking = false
    @State private var askingPermanent = false
    @State private var appliedFor = PerPreview<Job>()
    @State private var expired = false

    /// The apply started for THIS preview; one started for an earlier preview does not count.
    private var applied: Job? { appliedFor.value(for: preview?.id) }

    private var gate: ReviewApplyGate {
        if expired { return .expired }
        return session.selection.gate(previewID: preview?.id, finishedAt: preview?.finishedAt)
    }

    /// Why Apply is not available, or what its last try said: in words, in the bar.
    private var message: String? {
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

    private var applyDisabled: Bool {
        if gate != .ready || sentRows.isEmpty { return true }
        guard let applied else { return false }
        switch applied.state {
        case .queued, .running, .succeeded: return true
        case .failed, .cancelled: return false
        }
    }

    var body: some View {
        ReviewTableBody(nodes: tree.nodes(for: session, order: sortOrder, only: only), sortOrder: $sortOrder,
                        session: readOnly ? nil : session)
            .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            .confirmationDialog(confirmTitle, isPresented: $asking, titleVisibility: .visible) {
                Button(applyTitle, role: .destructive) { chosen() }
            } message: {
                Text(confirmation?.message ?? "")
            }
            .confirmationDialog("Delete Permanently?", isPresented: $askingPermanent, titleVisibility: .visible) {
                Button("Delete Permanently", role: .destructive) { apply() }
            } message: {
                Text("\(countText). \(confirmation?.permanent ?? "")")
            }
            .task(id: preview?.id) { await watchExpiry() }
            .task(id: applied?.id) { await watchApplied() }
    }

    // MARK: - the bar

    @ViewBuilder private var bar: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(readOnly ? session.readOnlySummary : summaryText).monospacedDigit()
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
                    .disabled(session.selectedRows.isEmpty)
                Button(applyTitle) { confirmation == nil ? apply() : (asking = true) }
                    .buttonStyle(.glassProminent)
                    .disabled(applyDisabled)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - applying

    /// What Apply would send: the caller's `approval` (or the ticks), narrowed to ticked, choosable
    /// rows. Applying, the bar and the confirmation all read this one set.
    private var sent: ApprovedSet {
        session.selection.narrowed(approval?(session) ?? session.approved)
    }

    private var sentRows: [ReviewRow] {
        let ids = Set(sent.approved)
        return session.rows.filter { ids.contains($0.id) }
    }

    private var sentBytes: Int64 { sentRows.compactMap(\.bytes).reduce(0, +) }

    /// "9 Items (8.5 GB)", from the rows that are sent.
    private var countText: String {
        let count = sentRows.count
        let items = "\(count) \(count == 1 ? "Item" : "Items")"
        return session.hasSizes ? "\(items) (\(ByteSize.format(sentBytes)))" : items
    }

    /// "12 selected · 3.2 GB · 3 kept", and where the selection reaches beyond the tab in view,
    /// "12 selected across 3 tabs" (or "12 selected, 5 in other tabs" when the tabs are not given).
    private var summaryText: String {
        let rows = sentRows
        var text = "\(rows.count) selected"
        if let only {
            let outside = rows.filter { !only.contains($0.id) }.count
            if outside > 0 {
                let spanned = tabs.filter { tab in rows.contains { tab.contains($0.id) } }.count
                text += spanned > 1 ? " across \(spanned) tabs" : ", \(outside) in other tabs"
            }
        }
        if session.hasSizes { text += " · \(ByteSize.format(sentBytes))" }
        if session.keptCount > 0 { text += " · \(session.keptCount) kept" }
        return text
    }

    private var confirmTitle: String {
        guard let confirmation else { return applyTitle }
        return "\(confirmation.verb) \(countText) \(confirmation.destination)?"
    }

    private func chosen() {
        if confirmation?.permanent != nil { askingPermanent = true } else { apply() }
    }

    private func apply() {
        guard gate == .ready, let preview else { return }
        let job = store.apply(from: preview, approved: sent)
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
        memo.value(for: session, key: Key(order: order, only: only)) {
            ReviewNode.tree(only.map { keep in session.rows.filter { keep.contains($0.id) } } ?? session.rows, order: order)
        }
    }

    private struct Key: Equatable {
        let order: [KeyPathComparator<ReviewNode>]
        let only: Set<String>?
    }
}
