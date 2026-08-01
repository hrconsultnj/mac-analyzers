import SwiftUI
import AnalyzersKit
import UIComponents

/// Update pane: installed vs latest release, one-click upgrade via the
/// repo's upgrade.command (runs in Terminal so progress is visible).
struct UpdateSettingsView: View {

    /// One release's notes, parsed from the bundled changelog.
    struct ReleaseNote: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    @State private var latest: String?
    @State private var checking = false
    @State private var notes: [ReleaseNote] = []

    private var installed: String { UpdateChecker.installedVersion }
    private var updateAvailable: Bool {
        latest.map { UpdateChecker.isNewer($0, than: installed) } ?? false
    }

    var body: some View {
        PaneScaffold(symbol: "arrow.down.circle.fill", color: .green, title: "Update",
                     caption: "Keep Mac Analyzers current, straight from the repo.") {
            Section {
                LabeledContent("Installed version") { Text("v\(installed)").monospacedDigit() }
                LabeledContent("Latest release") {
                    Text(latest.map { "v\($0)" } ?? (checking ? "checking…" : "—"))
                        .monospacedDigit()
                }
                if updateAvailable {
                    Label("Update available", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                } else if latest != nil {
                    Label("You're up to date", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Section {
                HStack {
                    Button(checking ? "Checking…" : "Check Now") {
                        Task {
                            checking = true
                            latest = await UpdateChecker.latestVersion(force: true)
                            checking = false
                        }
                    }
                    .disabled(checking)
                    Spacer()
                    Button("Install Update…") { GuardControl.runUpgrade() }
                        .buttonStyle(.glassProminent)
                        .disabled(!updateAvailable)
                }
                Text("Install opens Terminal and runs upgrade.command: pulls the latest version, rebuilds the app, refreshes the background agents, and relaunches. Your settings and protected lists are never touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !notes.isEmpty {
                Section("What's New") {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        DisclosureGroup(isExpanded: .constant(index == 0).animation()) {
                            Text(note.body)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        } label: {
                            Text(note.title)
                                .font(.callout.weight(.medium))
                        }
                    }
                }
            }
        }
        .onAppear {
            UserDefaults.standard.set(installed, forKey: "lastSeenChangelog")
            detachedLoad({ Self.loadNotes() }) { notes = $0 }
        }
        .task {
            // always fresh when the pane opens — the cache is for background
            // polling, not for the screen whose job is showing the truth
            checking = true
            latest = await UpdateChecker.latestVersion(force: true)
            checking = false
        }
    }

    /// Bundled at build time from the release-note commits; each "## vX.Y…"
    /// header starts one release.
    private nonisolated static func loadNotes() -> [ReleaseNote] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "## ")
            .filter { $0.hasPrefix("v") }
            .compactMap { block in
                let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
                guard let first = lines.first else { return nil }
                let body = lines.dropFirst().joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return ReleaseNote(title: String(first), body: body.isEmpty ? "—" : body)
            }
    }
}
