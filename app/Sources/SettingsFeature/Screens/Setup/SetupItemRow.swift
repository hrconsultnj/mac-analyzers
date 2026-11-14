import SwiftUI
import AnalyzersKit
import UIComponents

/// One thing in Setup: its state as a symbol and a word, what it gets the person, the evidence for the state, and the one
/// button. While the person is switching something on in System Settings the row shows the guidance in place.
struct SetupItemRow: View {
    let item: SetupItem
    let working: Bool
    let busy: Bool
    let session: SystemSettingsHandoff.Session?
    let confirmed: Bool
    let onAction: () -> Void
    let onCloseGuidance: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(systemName: item.state.symbol)
                .foregroundStyle(tone.tint)
                .imageScale(.large)
                .frame(width: 24)      // the state symbols differ in width: one column keeps every row's text aligned
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(spacing: Tokens.Space.s) {
                    Text(item.title).font(.callout.weight(.medium))
                    Text(confirmed ? "On — thank you" : item.state.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(confirmed ? Tokens.Status.safe.tint : tone.tint)
                }
                Text(item.why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // the evidence: a sentence about what was read on this Mac
                Text(item.evidence)
                    .font(.caption)
                    .foregroundStyle(item.state == .on ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if case .openSettings(let pane)? = item.action, let session {
                    SystemSettingsGuidance(pane: pane, session: session, stillOff: item.state != .on, onClose: onCloseGuidance)
                        .padding(.top, Tokens.Space.xs)
                }
            }
            Spacer(minLength: Tokens.Space.m)
            if let title = item.actionTitle, item.action != nil, session == nil {
                Button(working ? "Working…" : title, action: onAction)
                    .disabled(busy)
            }
        }
        .padding(.vertical, Tokens.Space.xs)
    }

    private var tone: Tokens.Tone {
        switch item.state {
        case .on: Tokens.Status.safe
        case .needsYou: Tokens.Status.destructive
        case .onlyApp, .notAskedYet: Tokens.Status.caution
        // Off is a warning only for a real problem; an optional choice left off is not one
        case .off: item.weight == .problem ? Tokens.Status.caution : Tokens.Status.inert
        case .cantTell: Tokens.Status.inert
        }
    }
}
