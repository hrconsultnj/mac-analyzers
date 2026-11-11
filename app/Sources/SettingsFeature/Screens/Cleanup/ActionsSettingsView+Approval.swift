import SwiftUI
import AnalyzersKit
import UIComponents

/// Per-item approval: the checkbox rows, the selection bar, the approved set the
/// engine is given, and the headline, button and prompt text built from it.
extension ActionsSettingsView {

    // MARK: - per-item approval
    //
    // "Apply only what you approve" was a claim about the button, not the
    // items. Deselecting a row now genuinely keeps it out of the apply: the
    // approved set is written to a file and the engine intersects its own
    // freshly-derived findings with it.

    /// A row wrapped in its own checkbox. `key` is what the engine will be
    /// given — a pid for processes, a path for files. Rows from a finished
    /// run pass nil and render plain, since there is nothing left to approve.
    /// `name` names the row for VoiceOver — the checkbox itself carries no
    /// visible label (`.labelsHidden()`), so without this it reads as an
    /// anonymous "checkbox".
    @ViewBuilder func selectable<Content: View>(
        _ key: String?, name: String, @ViewBuilder content: () -> Content
    ) -> some View {
        if let key, phase == .review {
            HStack(spacing: Tokens.Space.s) {
                Toggle(isOn: Binding(
                    get: { !deselected.contains(key) },
                    set: { on in
                        if on { deselected.remove(key) } else { deselected.insert(key) }
                    })) { EmptyView() }
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Include \(name) in this cleanup")
                content()
                    .opacity(deselected.contains(key) ? 0.45 : 1)
            }
        } else {
            content()
        }
    }

    var selectionBar: some View {
        HStack {
            Text(approvedCount == totalApprovable
                 ? "All \(totalApprovable) selected"
                 : "\(approvedCount) of \(totalApprovable) selected")
                .font(.callout.weight(.medium))
            Spacer()
            Button("Select All") { deselected.removeAll() }
                .disabled(deselected.isEmpty)
            Button("Select None") { deselected = Set(approvableKeys) }
                .disabled(approvedCount == 0)
        }
    }

    /// Every key that could be acted on in this run.
    private var approvableKeys: [String] {
        switch cleaner {
        case .memoryClean, .reclaim: dryReapItems.compactMap { $0.pid.map(String.init) }
        case .storageClean, .janitor:
            storageRun?.items.filter { $0.status == .dry }.map(\.path) ?? []
        case .tempClean:
            tempRun?.readyItems.map(\.path) ?? []
        }
    }

    /// Bytes still ticked in a temp review — what the permanent alert names.
    var tempSelectedBytes: Int64 {
        tempRun?.readyItems.filter { !deselected.contains($0.path) }
            .reduce(0) { $0 + $1.sizeBytes } ?? 0
    }

    private var totalApprovable: Int { approvableKeys.count }
    var approvedCount: Int { approvableKeys.filter { !deselected.contains($0) }.count }

    /// What the user left ticked, for `JobStore.apply(from:approved:)`. The
    /// kernel writes the approval file and passes the engine flag, always, so an
    /// apply acts on what was reviewed and nothing that appeared since. The
    /// storage cleaner's package-manager and tool prunes are reviewed with it:
    /// this screen shows them only as text and has no row to untick, so their
    /// keys (`prune:pnpm`) ride along while nothing was unticked, exactly when
    /// they ran before, and are left out once a row was unticked. The new
    /// Caches & Builds screen gives each its own row. A file that cannot be
    /// written stops the apply: it can never widen it to "everything".
    var approvedSet: ApprovedSet {
        // commands and stacks that are not rows here ride along while nothing was unticked
        let prunes = cleaner == .storageClean && deselected.isEmpty ? (storageRun?.prunes.map(\.key) ?? []) : []
        let stacks = isReapShaped && deselected.isEmpty ? dryReapItems.compactMap(\.stackKey).map { "stack:" + $0 } : []
        return ApprovedSet(approvable: approvableKeys + prunes + stacks, deselected: deselected)
    }

    var isApplyingOrDone: Bool {
        if case .applying = phase { return true }
        if case .done = phase { return true }
        return false
    }

    // MARK: - numbers for headlines and buttons

    /// What else an apply of the storage cleaner runs, said where the review is:
    /// the package-manager and tool cleanups have no row to untick here, so the
    /// rule is spelled out — they run only while nothing is unticked.
    var alsoRunsLine: String? {
        guard cleaner == .storageClean, let prunes = storageRun?.prunes, !prunes.isEmpty else { return nil }
        let names = prunes.map(\.title).joined(separator: "; ")
        return deselected.isEmpty
            ? "Also runs with this apply: \(names). These are skipped as soon as any row above is unticked."
            : "Not running, because a row is unticked: \(names). Select every row again and they run."
    }

    var isReapShaped: Bool { cleaner == .memoryClean || cleaner == .reclaim }

    /// What an apply can act on: every process with a pid, plus the orphaned
    /// stacks while nothing is unticked (a stack has no row to untick here, and
    /// the engine stops one only when its key is sent).
    var reapClosableCount: Int {
        dryReapItems.filter { $0.pid != nil }.count
            + (deselected.isEmpty ? dryReapItems.filter { $0.stackKey != nil }.count : 0)
    }

    var dryReapItems: [ReapItem] {
        reapRun?.allItems.filter { $0.status == .dry } ?? []
    }

    var dryStorageBytes: Int64 {
        storageRun?.items.filter { $0.status == .dry }.map(\.sizeBytes).reduce(0, +) ?? 0
    }

    /// A selection count now, not a "was anything found" count — deselect
    /// everything and Apply is correctly unavailable.
    var hasAnythingToApply: Bool { approvedCount > 0 }

    var reviewHeadline: String {
        switch cleaner {
        case .memoryClean, .reclaim:
            let mb = dryReapItems.compactMap(\.mb).reduce(0, +)
            return reapClosableCount == 0
                ? "Nothing to close — all clean."
                : "Would close \(reapClosableCount) process\(reapClosableCount == 1 ? "" : "es") (~\(mb) MB)"
        case .storageClean, .janitor:
            return dryStorageBytes == 0
                ? "Nothing stale to remove."
                : "Would free \(ByteSize.format(dryStorageBytes))"
        case .tempClean:
            let bytes = tempRun?.readyBytes ?? 0
            return bytes == 0
                ? "Nothing ready to clear."
                : recoverableNow
                    ? "Would move \(ByteSize.format(bytes)) to the Trash"
                    : "Would delete \(ByteSize.format(bytes)) permanently"
        }
    }

    var applyButtonTitle: String {
        switch cleaner {
        case .memoryClean, .reclaim:
            "Apply — close \(reapClosableCount)"
        case .storageClean:
            "Apply — free \(ByteSize.format(dryStorageBytes))"
        case .janitor:
            "Apply — trash \(ByteSize.format(dryStorageBytes))"
        case .tempClean:
            recoverableNow ? "Apply — trash \(ByteSize.format(tempSelectedBytes))"
                           : "Apply — delete \(ByteSize.format(tempSelectedBytes))"
        }
    }

    var applyPrompt: String {
        switch cleaner {
        case .memoryClean, .reclaim:
            "Close \(reapClosableCount) process\(reapClosableCount == 1 ? "" : "es")?"
        case .storageClean:
            "Remove the listed caches (\(ByteSize.format(dryStorageBytes)))?"
        case .janitor:
            "Move the listed items (\(ByteSize.format(dryStorageBytes))) to the Trash?"
        case .tempClean:
            recoverableNow
                ? "Move the ticked items (\(ByteSize.format(tempSelectedBytes))) to the Trash?"
                : "Permanently delete the ticked items (\(ByteSize.format(tempSelectedBytes)))?"
        }
    }
}
