import SwiftUI
import AppKit
import AgentFeature
import AnalyzersKit
import UIComponents

/// The live conversation (S2): the turns so far, the live turn's steps as
/// tool cards — each naming the real script it ran, with its own icon and
/// state — the agent's reasoning kept apart from its answer, and the reply
/// rendered as Markdown. The input is always here: a chat you can scroll back
/// through is a chat you keep talking to, including one reopened from
/// history. A permission request renders as the tick list that can only
/// shrink, and a finished turn that ends in an approval shows the receipt.
struct AskSessionView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AskSessionBox.self) private var conversation
    @Environment(JobStore.self) private var jobs
    @Environment(ConfigStore.self) private var config
    @State private var draft = ""
    @State private var scrollToBottom = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        if let session = conversation.current {
            screen(for: session)
        } else {
            // A restored stack (or a link) landing here with nothing running.
            DataScreen(title: Names.Screen.ask, subtitle: nil) {
                EmptyState("No Conversation Running", systemImage: "sparkles",
                           description: Text("Ask something on the Ask screen and the conversation shows up here."))
            }
        }
    }

    private func screen(for session: AskSession) -> some View {
        // one column: the transcript is what scrolls, the input is pinned at
        // the bottom edge — DataScreen renders builder siblings side by side,
        // which is how the input ended up "hovering" mid-window
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                        ForEach(session.turns) { turn in
                            archivedTurn(turn)
                        }
                        if session.phase != .idle || !session.prompt.isEmpty {
                            transcript(for: session)
                        }
                        Color.clear.frame(height: 1).id("ask-session-bottom")
                    }
                    .padding()
                }
                .onChange(of: scrollToBottom) {
                    proxy.scrollTo("ask-session-bottom", anchor: .bottom)
                }
            }
            Divider()
            inputRow(for: session)
                .padding(.horizontal, Tokens.Space.l)
                .padding(.vertical, Tokens.Space.s)
        }
        .navigationTitle(Names.Screen.ask)
        .navigationSubtitle(subtitle(for: session))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    session.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(session.phase != .working && session.phase != .awaitingApproval)
                .help("Stop this turn. Nothing has been changed.")
            }
        }
        .onChange(of: session.steps.count) { scrollToBottom += 1 }
        .onChange(of: session.reply) { scrollToBottom += 1 }
        .onChange(of: session.thinking) { scrollToBottom += 1 }
        .onChange(of: session.turns.count) { scrollToBottom += 1 }
        .onChange(of: session.phase) { scrollToBottom += 1 }
    }

    // MARK: - the input (always live, on every chat, ended or reopened)

    @ViewBuilder private func inputRow(for session: AskSession) -> some View {
        let busy = session.phase == .working || session.phase == .awaitingApproval
        HStack(spacing: Tokens.Space.m) {
            TextField(session.phase == .idle ? "Ask about this Mac…" : "Ask a follow-up…",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .disabled(busy)
                .onSubmit { sendDraft(session) }
            if busy {
                ProgressView().controlSize(.small)
                    .help("The agent is on it — Stop is in the toolbar")
            } else {
                Button {
                    sendDraft(session)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send the question to the agent")
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
        .padding(.vertical, Tokens.Space.s)
    }

    private func sendDraft(_ session: AskSession) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        inputFocused = true
        session.send(text, scan: (kind: JobKind.storageReport, intent: JobIntent.run),
                     config: sessionConfig, jobs: jobs)
    }

    private var sessionConfig: AgentSessionConfig {
        AgentSessionConfig(
            workingDirectory: AnalyzersPaths.suiteRoot,
            enabledCapabilities: config.agent.capabilities,
            prelude: config.agent.prelude)
    }

    // MARK: - the transcript

    /// One archived turn, read-only: the question, its tool cards, its answer.
    private func archivedTurn(_ turn: AskTurn) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            userLine(turn.prompt)
            ForEach(turn.steps) { step in
                toolCard(name: step.name, detail: step.detail, finished: step.finished)
            }
            if !turn.thinking.isEmpty {
                thinkingBlock(turn.thinking)
            }
            if !turn.reply.isEmpty {
                replyBlock(turn.reply, answeredBy: turn.engine)
            }
            if let failure = turn.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if turn.stopped {
                Label("Stopped — nothing has been changed.", systemImage: "stop.circle")
                    .foregroundStyle(.secondary)
            } else if let headline = turn.receiptHeadline {
                Label(headline, systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            }
            Divider()
        }
    }

    /// The live turn: everything as it streams.
    @ViewBuilder private func transcript(for session: AskSession) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            userLine(session.prompt)
        }
        ForEach(session.steps) { step in
            toolCard(name: step.name, detail: step.detail, finished: step.finished)
        }
        if !session.thinking.isEmpty {
            thinkingBlock(session.thinking)
        }
        if !session.reply.isEmpty {
            replyBlock(session.reply, answeredBy: session.engineTitle.isEmpty ? nil : session.engineTitle)
        }
        // the standing line, true until an approval exists — system voice
        if session.phase == .working {
            systemRow("Nothing has been changed yet.")
        }
        // the turn's own machinery, when it has something to say
        if let notice = session.notice {
            systemRow(notice)
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

    /// A system message: the app's own voice, with the app's own icon —
    /// never rendered as if the agent or the person said it.
    private func systemRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    /// The tile icon for the engine that answered: the vendor's own name in
    /// the label — the CLIs ship no icon file, so nothing is fabricated; the
    /// on-device engine gets the model chip.
    private func engineTile(for label: String) -> some View {
        let symbol = label.lowercased().contains("on-device") ? "memorychip"
            : label.lowercased().contains("custom") ? "slider.horizontal.3"
            : "terminal"
        return IconTile(symbol: symbol, color: .mint, side: 24).accessibilityHidden(true)
    }

    private func userLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            IconTile(symbol: "person.crop.circle", color: .indigo, side: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("You").font(.caption).foregroundStyle(.secondary)
                Text(text).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - the tool cards

    /// One step as a card: the tool's own icon, its name, the real script in
    /// monospace, and its state — a spinner while it runs, a checkmark when
    /// done. The detail is the point: the person sees exactly what ran.
    private func toolCard(name: String, detail: String, finished: Bool) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            IconTile(symbol: Self.toolSymbol(for: name), color: .mint, side: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                HStack(spacing: Tokens.Space.s) {
                    Text(name).font(.callout.weight(.medium))
                    if finished {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.mint)
                            .accessibilityLabel("\(name) finished")
                    } else {
                        ProgressView().controlSize(.mini)
                            .accessibilityLabel("\(name) running")
                    }
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s)
        .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
        .accessibilityElement(children: .combine)
    }

    /// The icon a step's name maps to — the shape of the work, not decoration.
    static func toolSymbol(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("scan") || lowered.contains("storage scan")
            || lowered.contains("memory scan") || lowered.contains("network") { return "magnifyingglass" }
        if lowered.contains("report") || lowered.contains("read") { return "doc.text.magnifyingglass" }
        if lowered.contains("preview") || lowered.contains("propose") || lowered.contains("clean") { return "trash" }
        if lowered.contains("approv") || lowered.contains("appl") { return "checkmark.seal" }
        if lowered.contains("sugges") || lowered.contains("rule") { return "lightbulb" }
        if lowered.contains("protect") { return "shield.lefthalf.filled" }
        return "gearshape"
    }

    // MARK: - thinking and the reply

    /// The agent's reasoning, in its own collapsible — present, never mixed
    /// into the answer.
    private func thinkingBlock(_ text: String) -> some View {
        // one disclosed block, not rows
        DisclosureGroup {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Thinking", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The answer, labelled with the engine — and model, when one is loaded —
    /// that produced it, and rendered as Markdown: headings, lists and code in
    /// the model's own structure instead of a wall of characters.
    private func replyBlock(_ text: String, answeredBy: String?) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            engineTile(for: answeredBy ?? "")
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(answeredBy ?? "Sparehold")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                markdown(text)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    /// Markdown → attributed text; a body that does not parse shows as-is
    /// rather than vanishing.
    private func markdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
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
                Text("Ask a follow-up below, or start something new from the Ask screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - naming

    private func subtitle(for session: AskSession) -> String {
        switch session.phase {
        case .idle: session.turns.isEmpty ? "New" : "\(session.turns.count) turn\(session.turns.count == 1 ? "" : "s")"
        case .working: "Working…"
        case .awaitingApproval: "Waiting for your answer"
        case .done: session.receipt == nil ? "Ended" : "Done"
        }
    }

    /// The engine proposes stable identifiers ("cleaner:downloads-janitor");
    /// until the tool registry names its actions, the identifier reads as
    /// words: "Downloads Janitor".
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
