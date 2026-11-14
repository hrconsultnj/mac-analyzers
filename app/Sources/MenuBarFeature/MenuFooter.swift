import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The footer shared by every tab, and the small helpers the tabs share.
extension MenuContentView {

    var footer: some View {
        HStack {
            Button {
                ActivationPolicy.windowOpening()
                openWindow(id: "main")
            } label: {
                Label("Open \(Names.app)", systemImage: "macwindow")
            }
            if let title = updates.availableTitle {
                Button(title) { updates.requestInstall() }
                    .buttonStyle(.borderedProminent)
                    .help("Update in Terminal, then relaunch; settings are kept")
            } else {
                Text(updates.build.shortVersionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(updates.build.versionText)        // the full version, build metadata included
            }
            Spacer()
            Button {
                GuardControl.restartApp()
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .help("Restart this app only — nothing else is touched")
            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    func runText(_ date: Date?) -> String {
        guard let date else { return "never" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
