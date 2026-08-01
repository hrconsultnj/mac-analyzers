import SwiftUI
import AnalyzersKit
import UIComponents

/// Storage pane: auto-clean scope lists + recordings folder.
struct StorageSettingsView: View {
    @Environment(ConfigStore.self) private var config

    var body: some View {
        @Bindable var config = config
        PaneScaffold(symbol: "internaldrive.fill", color: .indigo, title: "Storage",
                     caption: "What the scheduled cleans may touch. Everything is rebuildable; documents are never in scope.") {
            Section("Storage auto-clean") {
                StringListEditor(
                    title: "Extra cache-directory globs (cleaned when idle > 7 days)",
                    prompt: "e.g. ~/.someapp/cache/.next-*",
                    items: $config.storage.extraCacheGlobs
                )
                AppListEditor(
                    title: "Stale apps (cleanup offers to remove, per app)",
                    mode: .installedApps,
                    items: $config.storage.staleApps
                )
                LabeledContent("Recordings folder") {
                    TextField("empty = feature disabled", text: $config.storage.recordingsDir)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                SaveBar { try config.save() }
                Text("Applies on the next scheduled run (daily 8:00 AM / deep every 3 days).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
