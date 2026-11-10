import SwiftUI
import AnalyzersKit
import UIComponents

/// One app, tool or service as ONE line you can act on.
///
/// The line carries the name, what it is made of ("8 tabs and pages, 3
/// extensions, 5 helpers"), the memory it holds in total, and a single Quit
/// for the whole thing. Opening it shows the same processes summarized by
/// what they do; opening one of those shows the processes themselves. Three
/// levels, so a 30-process browser never has to be read as a 30-row list —
/// and nobody has to guess which of the 30 is safe to end.
struct MonitorFamilyRow: View {

    let group: CensusGroup
    /// Refresh the list (called once macOS has had time to act on a quit).
    let reload: () -> Void
    let openDossier: (LiveProcess) -> Void

    @State private var confirmingQuit = false
    @State private var quitting = false

    var body: some View {
        DisclosureGroup {
            if group.parts.count > 1 {
                ForEach(group.parts) { part in
                    DisclosureGroup {
                        processRows(part.members)
                    } label: {
                        partLabel(part)
                    }
                }
            } else {
                // every process does the same job — nothing to summarize
                processRows(group.members)
            }
        } label: {
            label
                .contextMenu {
                    Button("Dossier…") { openDossier(group.lead) }
                    if group.quit != .unavailable {
                        Button("\(quitVerb) \(group.name)…") { confirmingQuit = true }
                    }
                }
        }
        .confirmationDialog(confirmTitle, isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button("\(quitVerb) \(group.name)", role: .destructive) { quit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private func processRows(_ processes: [LiveProcess]) -> some View {
        ForEach(processes) { process in
            ProcessRow(proc: process, afterStop: reload)
        }
    }

    // MARK: - the group line

    private var label: some View {
        HStack(spacing: Tokens.Space.m) {
            icon
                .accessibilityHidden(true)  // decorative — the name next to it says who this is
            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                Text(group.name)
                    .font(Tokens.Typography.rowTitleKey)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Tokens.Space.s)
            Text(group.totalText)
                .font(Tokens.Typography.valueKey)
                .foregroundStyle(.secondary)
            quitControl
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, Tokens.Space.xxs)
    }

    /// What it is made of when that says something; otherwise what it is
    /// for; otherwise where to find it.
    private var subtitle: String {
        let count = "\(group.members.count) processes"
        if let summary = group.partsSummary { return "\(count) — \(summary)" }
        if let role = group.role { return "\(count) · \(role)" }
        return "\(count) · pid \(group.lead.pid)"
    }

    @ViewBuilder private var icon: some View {
        if let app = NSRunningApplication(processIdentifier: pid_t(group.lead.pid)),
           let image = app.icon {
            Image(nsImage: image).resizable()
                .frame(width: Tokens.Icon.row, height: Tokens.Icon.row)
        } else {
            switch group.category {
            case .apps: IconTile(symbol: "square.stack.3d.up.fill", color: .orange, side: Tokens.Icon.row)
            case .tools: IconTile(symbol: "terminal.fill", color: .blue, side: Tokens.Icon.row)
            case .system: IconTile(symbol: "gearshape.fill", color: .gray, side: Tokens.Icon.row)
            }
        }
    }

    @ViewBuilder private var quitControl: some View {
        if group.quit == .unavailable {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("Part of macOS — it runs as long as your Mac does, and isn't something to quit from here")
                .accessibilityLabel("Part of macOS, not quittable here")
        } else {
            Button(quitting ? "…" : quitVerb) { confirmingQuit = true }
                .controlSize(.small)
                .disabled(quitting)
                .help(group.quit.isApp
                      ? "Quit \(group.name) and all \(group.members.count) of its processes — the same as ⌘Q, save prompts still appear"
                      : "Ask \(group.name) to stop, along with everything it started")
                .accessibilityLabel("\(quitVerb) \(group.name)")
        }
    }

    // MARK: - one job inside the group

    private func partLabel(_ part: CensusPart) -> some View {
        HStack(spacing: Tokens.Space.m) {
            Text(part.title)
                .font(Tokens.Typography.rowTitle)
            Text(part.members.count == 1 ? "1 process" : "\(part.members.count) processes")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.s)
            Text(part.totalText)
                .font(Tokens.Typography.value)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - quitting the whole thing

    private var quitVerb: String { group.quit.isApp ? "Quit" : "Stop" }

    private var confirmTitle: String { "\(quitVerb) \(group.name)?" }

    private var confirmMessage: String {
        let helpers = group.members.count - 1
        if group.quit.isApp {
            let who = helpers > 0
                ? "\(group.name) and its \(helpers) helper process\(helpers == 1 ? "" : "es") will close"
                : "\(group.name) will close"
            return "\(who), giving back about \(group.totalText). It will still ask before discarding unsaved work."
        }
        let what = group.members.count == 1 ? "It" : "All \(group.members.count) of its processes"
        return "\(what) will be asked to stop, giving back about \(group.totalText). Anything in progress is interrupted."
    }

    private func quit() {
        quitting = true
        GuardControl.quit(group.quit)
        Task { @MainActor in
            // an app takes a moment to close its helpers behind it
            try? await Task.sleep(for: .seconds(2))
            reload()
            quitting = false
        }
    }
}

private extension CensusGroup.QuitScope {
    var isApp: Bool {
        if case .app = self { return true }
        return false
    }
}
