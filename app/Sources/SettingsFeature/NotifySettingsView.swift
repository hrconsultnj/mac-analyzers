import SwiftUI
import AnalyzersKit
import NotifierKit
import UIComponents

/// Notifications pane: viewer app, fallback-timeout, maintenance actions.
struct NotifySettingsView: View {
    @Environment(ConfigStore.self) private var config
    @State private var permissionStatus: String?

    var body: some View {
        @Bindable var config = config
        PaneScaffold(symbol: "bell.badge.fill", color: .red, title: "Notifications",
                     caption: "How alerts behave, and the fix-it levers when they don't.") {
            Section("Notification behavior") {
                Picker("Clicking a notification opens logs in", selection: $config.notify.logViewer) {
                    Text("TextEdit").tag("TextEdit")
                    Text("Console").tag("Console")
                    Text("Visual Studio Code").tag("Visual Studio Code")
                }
                Stepper("Fallback (alerter) auto-close: \(config.notify.timeoutSeconds) s",
                        value: $config.notify.timeoutSeconds, in: 30...600, step: 30)
            }

            Section("Maintenance") {
                VStack(alignment: .leading, spacing: 2) {
                    Button("Fix notifications…") {
                        NotificationPoster.shared.reRequestPermission { permissionStatus = $0 }
                    }
                    if let permissionStatus {
                        Text(permissionStatus).font(.caption).foregroundStyle(.blue)
                    }
                    Text("Re-asks macOS for permission when possible; otherwise opens this app's notification pane so you can adjust allow/style/previews. No Mac restart involved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Button("Restart Mac Analyzers") { GuardControl.restartApp() }
                    Text("Relaunches only this menu-bar app — your other work, sessions, and the background agents keep running untouched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Button("Restart memory guard") { GuardControl.restartGuard() }
                    Text("Restarts the background watcher process so saved limits and lists apply immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                SaveBar { try config.save() }
                Text("Persistence (banner vs. alert style) and lock-screen previews are per-app macOS settings: System Settings → Notifications → Mac Analyzers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
