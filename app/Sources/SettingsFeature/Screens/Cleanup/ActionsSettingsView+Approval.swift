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
            Button("Select all") { deselected.removeAll() }
                .disabled(deselected.isEmpty)
            Button("Select none") { deselected = Set(approvableKeys) }
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
    /// kernel writes the approval file and passes the engine flag; nothing
    /// deselected means no flag at all, so the common case runs exactly the
    /// command it always did, and temp clean always sends its list (temp
    /// folders change by the minute). A file that cannot be written stops the
    /// apply: it can never widen it to "everything".
    var approvedSet: ApprovedSet {
        ApprovedSet(approvable: approvableKeys, deselected: deselected)
    }

    var isApplyingOrDone: Bool {
        if case .applying = phase { return true }
        if case .done = phase { return true }
        return false
    }

    // MARK: - numbers for headlines and buttons

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
            return dryReapItems.isEmpty
                ? "Nothing to close — all clean."
                : "Would close \(dryReapItems.count) process\(dryReapItems.count == 1 ? "" : "es") (~\(mb) MB)"
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
            "Apply — close \(dryReapItems.count)"
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
            "Close \(dryReapItems.count) process\(dryReapItems.count == 1 ? "" : "es")?"
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
