import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The footer shared by every tab, and the small helpers the tabs share.
extension MenuContentView {

    // MARK: - shared

    var footer: some View {
        HStack {
            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            if let latest = latestVersion,
               UpdateChecker.isNewer(latest, than: UpdateChecker.installedVersion) {
                Button("Upgrade to v\(latest)") { GuardControl.runUpgrade() }
                    .buttonStyle(.borderedProminent)
                    .help("Runs upgrade.command in Terminal — pull, rebuild, relaunch; settings untouched")
            } else {
                Text("v\(UpdateChecker.installedVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                GuardControl.restartApp()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Restart this app only — nothing else is touched")
            .accessibilityLabel("Restart app")
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.regular)
        .task { latestVersion = await UpdateChecker.latestVersion() }
    }

    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    func runText(_ date: Date?) -> String {
        guard let date else { return "never" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
