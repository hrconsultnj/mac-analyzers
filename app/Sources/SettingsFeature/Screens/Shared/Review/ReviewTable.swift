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
        if gate != .ready || session.selectedRows.isEmpty { return true }
        guard let applied else { return false }
        switch applied.state {
        case .queued, .running, .succeeded: return true
        case .failed, .cancelled: return false
        }
    }

    var body: some View {
        ReviewTableBody(nodes: tree.nodes(for: session, order: sortOrder), sortOrder: $sortOrder,
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
                Text(readOnly ? session.readOnlySummary : session.summary).monospacedDigit()
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
                    .disabled(session.selectedRows.count == session.choosableCount)
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

    /// "9 Items (8.5 GB)", from the same numbers as the bar.
    private var countText: String {
        let count = session.selectedRows.count
        let items = "\(count) \(count == 1 ? "Item" : "Items")"
        return session.hasSizes ? "\(items) (\(ByteSize.format(session.selectedBytes)))" : items
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
        let job = store.apply(from: preview, approved: session.approved)
        appliedFor.set(job, for: preview.id)
        onApplied(job)
    }

    /// Apply turns itself off, saying "Preview Again", the moment the review window passes.
    private func watchExpiry() async {
        expired = false
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

/// The grouped, sorted tree, rebuilt when the session (a different review) or the sort
/// changes, never on a tick: a tick must not regroup thousands of rows.
@MainActor
final class ReviewTreeCache {
    private let memo = IdentityMemo<ReviewSession, [KeyPathComparator<ReviewNode>], [ReviewNode]>()

    func nodes(for session: ReviewSession, order: [KeyPathComparator<ReviewNode>]) -> [ReviewNode] {
        memo.value(for: session, key: order) { ReviewNode.tree(session.rows, order: order) }
    }
}
