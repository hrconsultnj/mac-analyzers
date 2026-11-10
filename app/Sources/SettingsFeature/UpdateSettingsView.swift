import SwiftUI
import AnalyzersKit
import UIComponents

/// Update pane: installed vs latest release, one-click upgrade via the
/// repo's upgrade.command (runs in Terminal so progress is visible).
struct UpdateSettingsView: View {

    @State private var latest: String?
    @State private var checking = false
    @State private var notes: [ReleaseNote] = []
    /// Which entries the reader opened or closed, by entry id.
    @State private var expanded: [String: Bool] = [:]

    private var installed: String { UpdateChecker.installedVersion }
    private var updateAvailable: Bool {
        latest.map { UpdateChecker.isNewer($0, than: installed) } ?? false
    }

    var body: some View {
        PaneScaffold(symbol: "arrow.down.circle.fill", color: .green, title: "Update",
                     caption: "See what version you have, what is new, and install the latest.") {
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
                        DisclosureGroup(isExpanded: expansion(of: note, isNewest: index == 0)) {
                            ReleaseNoteBody(note: note)
                        } label: {
                            Text(note.title)
                                .font(.callout.weight(.medium))
                        }
                    }
                }
            }
        }
        .task {
            UserDefaults.standard.set(installed, forKey: "lastSeenChangelog")
            await awaitLoad({ ReleaseNote.bundled() }) { notes = $0 }
        }
        .task {
            // always fresh when the pane opens — the cache is for background
            // polling, not for the screen whose job is showing the truth
            checking = true
            latest = await UpdateChecker.latestVersion(force: true)
            checking = false
        }
    }

    /// The newest entry starts open; every entry can be opened and closed.
    /// (The binding used to be a constant, so older releases could never be
    /// read at all — their arrows did nothing.)
    private func expansion(of note: ReleaseNote, isNewest: Bool) -> Binding<Bool> {
        Binding(
            get: { expanded[note.id] ?? isNewest },
            set: { expanded[note.id] = $0 })
    }
}
