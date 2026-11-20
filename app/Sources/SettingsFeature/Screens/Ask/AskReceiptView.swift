import SwiftUI
import AgentFeature
import AnalyzersKit
import UIComponents

/// The receipt a cleanup leaves (S4): the outcome first, in the person's own
/// terms, then what moved, what the protected list held back, and how long it
/// took — with Undo, the full receipt in Activity, and the way back to Ask.
/// The byte sentence ("41 GB → 44.9 GB free") fills in once an engine runs a
/// real apply; the v1 preview engine proposes only, and the outcome says so.
struct AskReceiptView: View {
    let receipt: AskSession.Receipt
    /// Back to the Ask home (the session screen pops; the shell owns the stack).
    let onAskSomethingElse: () -> Void
    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(receipt.headline)
                    .font(.headline)
                if let freed = receipt.freedLine {
                    Text(freed)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    LabeledContent("Approved", value: "\(receipt.approvedCount) of \(receipt.proposedCount)")
                    LabeledContent("Left Alone (Protected)", value: "\(receipt.skippedProtected)")
                    LabeledContent("Time", value: durationText)
                }
                .padding(Tokens.Space.s)
            }
            HStack(spacing: Tokens.Space.l) {
                Button("Undo This Cleanup") {
                    navigator.open(target: "undo")
                }
                .help("Put back what this cleanup moved, from the Undo screen")
                Button("See the Receipt") {
                    navigator.open(target: "activity")
                }
                .help("Every run this cleanup made, listed in Activity")
                Button("Ask Something Else", action: onAskSomethingElse)
            }
        }
    }

    /// "1m 24s", "12s" — the same shape the Activity rows use.
    private var durationText: String {
        let seconds = Int(receipt.duration.rounded())
        if seconds >= 60 {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
        return "\(seconds)s"
    }
}
