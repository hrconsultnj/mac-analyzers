import SwiftUI
import AgentFeature
import AnalyzersKit
import UIComponents

/// Ask: the agent's home (S1) — a health summary written from the latest
/// reports, the template grid, the chat input, and the trust line. A template
/// press and a typed message start the SAME loop: both send a prompt and push
/// the session screen (`Route.ask(.session)`), where the steps stream in.
struct AskHomeView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(JobStore.self) private var jobs
    @Environment(ConfigStore.self) private var config
    @Environment(AskSessionBox.self) private var conversation
    @State private var history = AskHistoryStore.shared
    @State private var draft = ""
    /// The summary line, read once when the screen appears (the reports walk
    /// the data root, so the read stays out of the body).
    @State private var healthSummary: String?

    var body: some View {
        PaneScaffold(symbol: "sparkles", color: .mint, title: Names.Screen.ask,
                     caption: "Ask about this Mac in your own words.") {
            if let healthSummary {
                Section {
                    Text(healthSummary)
                } header: {
                    Text("This Mac")
                }
            }
            Section {
                templateGrid
            } header: {
                Text("Start With a Question")
            }
            if !history.conversations.isEmpty {
                Section {
                    ForEach(history.conversations) { conversation in
                        historyRow(conversation)
                    }
                } header: {
                    Text("Recent Conversations")
                } footer: {
                    Text("Pick up where a chat left off — everything it did is in the transcript, and you can keep talking.")
                }
            }
            Section {
                chatInput
                // The feature's one promise, true at every phase.
                Text("Runs on this Mac, nothing leaves, and nothing is deleted without the list being shown first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Ask Anything")
            }
        }
        .task {
            healthSummary = Self.summarizeHealth()
            history.loadIfNeeded()
        }
    }

    // MARK: - the grid (b: 2×2 of template cards)

    private var templateGrid: some View {
        Grid(horizontalSpacing: Tokens.Space.m, verticalSpacing: Tokens.Space.m) {
            ForEach(Array(AskTemplate.gridRows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { template in
                        card(template)
                    }
                }
            }
        }
    }

    private func card(_ template: AskTemplate) -> some View {
        Button {
            start(template.prompt, scan: (template.scanKind, template.scanIntent))
        } label: {
            HStack(spacing: Tokens.Space.l) {
                IconTile(symbol: template.symbol, color: .mint, side: 28)
                    .accessibilityHidden(true)  // decorative — the title beside it names the template
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    Text(template.title)
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(template.prompt)
    }

    // MARK: - the chat input (c)

    private var chatInput: some View {
        HStack(spacing: Tokens.Space.m) {
            TextField("Ask about this Mac…", text: $draft)
                .onSubmit { sendDraft() }
            Button {
                sendDraft()
            } label: {
                Label("Send", systemImage: "arrow.up.circle.fill")
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Send the question to the agent")
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // A typed question's scan beat is the storage analyzer — the same
        // read-only report the templates start from.
        start(text, scan: (kind: JobKind.storageReport, intent: JobIntent.run))
    }

    // MARK: - starting a session

    private func start(_ prompt: String, scan: (kind: JobKind, intent: JobIntent)) {
        let sessionConfig = AgentSessionConfig(
            workingDirectory: AnalyzersPaths.suiteRoot,
            enabledCapabilities: config.agent.capabilities,
            prelude: config.agent.prelude)
        conversation.current = AskSession.begin(prompt: prompt, scan: scan,
                                                config: sessionConfig, jobs: jobs)
        draft = ""
        navigator.push(.ask(.session))
    }

    // MARK: - the history list

    /// One past conversation: its title, its age, and the way back in. A
    /// context menu deletes it — to the Trash, like everything else here.
    private func historyRow(_ conversation: AskConversation) -> some View {
        Button {
            self.conversation.current = self.conversation.session(for: conversation.id)
                ?? AskSession.reopened(from: conversation)
            navigator.push(.ask(.session))
        } label: {
            HStack(spacing: Tokens.Space.l) {
                IconTile(symbol: "sparkles", color: .mint, side: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    Text(conversation.title)
                        .lineLimit(1)
                    Text("\(conversation.turns.count) turn\(conversation.turns.count == 1 ? "" : "s") · "
                         + conversation.started.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.m)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Conversation", role: .destructive) {
                AskHistoryStore.shared.delete(conversation)
            }
        }
    }

    // MARK: - the health summary (a)

    /// A few plain facts from what the suite already knows: free space, memory
    /// pressure, and how fresh the latest reports are. A plain sentence — this
    /// is the screen's content, not an empty or loading state.
    static func summarizeHealth() -> String {
        var facts: [String] = []
        if let disk = LiveStats.diskUsage() {
            facts.append("\(disk.freeText) free of \(disk.totalText)")
        }
        switch LiveStats.memoryPressure() {
        case .normal: facts.append("memory pressure is normal")
        case .warning, .critical: facts.append("memory pressure needs attention")
        }
        let reports = ReportLibrary.all()
        let kindsSeen = Set(reports.map(\.kind))
        for kind in ReportDocument.Kind.allCases where kindsSeen.contains(kind) {
            if let newest = reports.first(where: { $0.kind == kind }) {
                facts.append("newest \(kind == .memory ? "memory" : "storage") report "
                             + newest.date.formatted(.relative(presentation: .named)))
            }
        }
        if kindsSeen.count < ReportDocument.Kind.allCases.count {
            facts.append("your first Ask scan writes the rest")
        }
        return facts.joined(separator: " · ") + "."
    }
}
