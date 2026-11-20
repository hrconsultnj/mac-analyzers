import SwiftUI
import AgentFeature
import AnalyzersKit
import UIComponents

/// The live conversation (S2): the user's message, then the steps streaming in
/// as they run — each naming the real script it ran — then the reply. While the
/// turn works, a standing line says nothing has been changed. A permission
/// request renders here as the tick list that can only shrink (the reviewed
/// preview screen takes it over when Phase 5 wires the population), and a
/// finished turn that ends in an approval hands the screen to the receipt (S4).
struct AskSessionView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AskSessionBox.self) private var conversation
    @State private var scrollToBottom = 0

    var body: some View {
        if let session = conversation.current {
            screen(for: session)
        } else {
            // A restored stack (or a link) landing here with nothing running.
            DataScreen(title: Names.Screen.ask, subtitle: nil) {
                EmptyState("No Conversation Running", systemImage: "text.bubble",
                           description: Text("Ask something on the Ask screen and the conversation shows up here."))
            }
        }
    }

    private func screen(for session: AskSession) -> some View {
        DataScreen(title: Names.Screen.ask, subtitle: subtitle(for: session)) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                        transcript(for: session)
                        Color.clear.frame(height: 1).id("ask-session-bottom")
                    }
                    .padding()
                }
                .onChange(of: scrollToBottom) {
                    proxy.scrollTo("ask-session-bottom", anchor: .bottom)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    session.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(session.phase == .done)
                .help("Stop this turn. Nothing has been changed.")
            }
        }
        .onChange(of: session.steps.count) { scrollToBottom += 1 }
        .onChange(of: session.reply) { scrollToBottom += 1 }
        .onChange(of: session.phase) { scrollToBottom += 1 }
    }

    // MARK: - the transcript

    @ViewBuilder private func transcript(for session: AskSession) -> some View {
        // the user's message
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("You Asked").font(.caption).foregroundStyle(.secondary)
            Text(session.prompt)
        }
        // the steps, in order, each naming the real script
        ForEach(session.steps) { step in
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                if step.finished {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.mint)
                        .accessibilityHidden(true)  // decorative — the text says the step ran
                } else {
                    ProgressView().controlSize(.small)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    Text(step.name)
                    Text(step.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        // the reply, as it grows
        if !session.reply.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("Sparehold").font(.caption).foregroundStyle(.secondary)
                Text(session.reply)
            }
        }
        // the standing line, true until an approval exists
        if session.phase == .working {
            Text("Nothing has been changed yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // the permission round-trip
        if let request = session.request, session.phase == .awaitingApproval {
            approval(request: request, session: session)
        }
        // the turn's end
        if session.phase == .done {
            ending(for: session)
        }
    }

    // MARK: - the approval list (S3's v1 rendering)

    private func approval(request: AgentPermissionRequest, session: AskSession) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Label(request.title, systemImage: "hand.raised")
                    .font(.callout.weight(.medium))
                ForEach(request.proposedActions, id: \.self) { action in
                    tickRow(action: action, session: session)
                }
                Text(summary(ticked: session.ticked.count, of: request.proposedActions.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: Tokens.Space.l) {
                    Button("Do It") {
                        session.respond(approvedActions: request.proposedActions
                            .filter { session.ticked.contains($0) })
                    }
                    .disabled(session.ticked.isEmpty)
                    .help("Run only the ticked actions, through the reviewed preview")
                    Button("Not Now") {
                        session.decline()
                    }
                    .help("Approve nothing; nothing runs")
                }
            }
            .padding(Tokens.Space.s)
        }
    }

    private func tickRow(action: String, session: AskSession) -> some View {
        Toggle(isOn: Binding(
            get: { session.ticked.contains(action) },
            // The only write is removal: the approved set can shrink, never grow.
            set: { if !$0 { session.untick(action) } }
        )) {
            Text(displayName(for: action))
        }
        .disabled(!session.ticked.contains(action))  // an unticked row stays unticked
    }

    private func summary(ticked: Int, of proposed: Int) -> String {
        let base = "\(ticked) of \(proposed) will run. Unticking only removes — the list can never grow."
        return ticked == 0 ? "Nothing ticked, so nothing would run. " + base : base
    }

    // MARK: - the turn's end (S4 lives here until it routes on its own)

    @ViewBuilder private func ending(for session: AskSession) -> some View {
        if let receipt = session.receipt {
            AskReceiptView(receipt: receipt) {
                navigator.setPath([])
            }
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                if let failure = session.failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    // a Stop, a Not Now, or a turn that ended without a plan
                    Label("Stopped — nothing has been changed.",
                          systemImage: session.stopped ? "stop.circle" : "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                Button("Ask Something Else") {
                    navigator.setPath([])
                }
            }
        }
    }

    // MARK: - naming

    private func subtitle(for session: AskSession) -> String {
        switch session.phase {
        case .working: "Working…"
        case .awaitingApproval: "Waiting for your answer"
        case .done: session.receipt == nil ? "Ended" : "Done"
        }
    }

    /// The engine proposes stable identifiers ("cleaner:downloads-janitor");
    /// until the tool registry names its actions (the engines lane), the
    /// identifier reads as words: "Downloads Janitor".
    private func displayName(for action: String) -> String {
        let parts = action.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return action }
        let body = parts[1]
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "=", with: " — ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2",
                                  options: .regularExpression, range: nil)
        return body.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
