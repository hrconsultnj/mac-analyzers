import SwiftUI
import AnalyzersKit
import UIComponents

/// Update pane: installed vs latest release, one-click upgrade via the
/// repo's upgrade.command (runs in Terminal so progress is visible).
struct UpdateSettingsView: View {
    @State private var latest: String?
    @State private var checking = false

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
        }
        .task {
            checking = true
            latest = await UpdateChecker.latestVersion()
            checking = false
        }
    }
}
