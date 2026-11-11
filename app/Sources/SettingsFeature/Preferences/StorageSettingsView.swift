import SwiftUI
import AnalyzersKit
import UIComponents

/// Storage pane: auto-clean scope lists + recordings folder.
struct StorageSettingsView: View {
    @Environment(ConfigStore.self) private var config
    @State private var backups: [IOSBackup]?

    var body: some View {
        @Bindable var config = config
        PaneScaffold(symbol: "internaldrive.fill", color: .indigo, title: Names.Screen.storageSettings,
                     caption: "What the scheduled cleans may touch — build output and caches only, all of it regenerable. The Downloads janitor is separate: it moves old files to the Trash, after you review them, and you can undo it.") {
            Section("Storage Auto-Clean") {
                StringListEditor(
                    title: "Extra cache-directory patterns (cleaned when idle > 7 days)",
                    prompt: "e.g. ~/.someapp/cache/.next-*",
                    items: $config.storage.extraCacheGlobs
                )
                AppListEditor(
                    title: "Stale apps (cleanup offers to remove, per app)",
                    mode: .installedApps,
                    items: $config.storage.staleApps,
                    height: 140
                )
                LabeledContent("Recordings Folder") {
                    TextField("empty = feature disabled", text: $config.storage.recordingsDir)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                ForEach(ToolCache.allCases) { tool in
                    Toggle(isOn: toolBinding(tool, in: $config.storage.toolCaches)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.title)
                            Text(tool.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Tool Caches (Expansion Pack)")
            } footer: {
                Text("Opt-in per tool. Everything here is redownloadable or rebuildable cache — sources and state are never in scope. Sizes show every time you preview; cleaning happens when you apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $config.storage.nmAgeDays, in: 1...60) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Remove node_modules after \(config.storage.nmAgeDays) idle \(config.storage.nmAgeDays == 1 ? "day" : "days")")
                        Text("A repo counts as idle when none of its source files changed — build output doesn't count. Reinstall with your package manager.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $config.storage.nmRequireClean) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Only when the git tree is clean")
                        Text("Off: idle repos lose node_modules even with uncommitted changes — your source files are never touched either way.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $config.storage.turboCacheMaxGB, in: 1...50) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Turborepo cache cap: \(config.storage.turboCacheMaxGB) GB per repo")
                        Text("Each build adds an entry; the oldest beyond the cap are removed on every run, even in active repos. Never while turbo is running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $config.storage.worktreeIdleDays, in: 0...60) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(config.storage.worktreeIdleDays == 0
                             ? "Idle worktrees: off"
                             : "Remove worktrees idle \(config.storage.worktreeIdleDays) \(config.storage.worktreeIdleDays == 1 ? "day" : "days")")
                        Text("Every idle worktree goes, merged or not, and nothing is lost: its commits stay on its branch, uncommitted changes are parked as a pinned commit in the repo, and local-only files (an .env, a database, notes) are copied aside first. Each removal is listed with the commands that bring it back. Never removed: main, locked worktrees, or one a terminal or agent session is sitting in. Deep clean only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Code Projects")
            }

            // The janitor is the ONE cleaner that touches documents rather
            // than rebuildable caches, and its settings were reachable only by
            // hand-editing a shell file — so the pane's promise that keep
            // patterns are honoured had no way to be acted on.
            Section {
                Stepper(value: $config.storage.janitorDownloadsDays, in: 1...365) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Downloads older than \(config.storage.janitorDownloadsDays) days")
                        Text("Counted from when you last opened or changed the file, not when you downloaded it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $config.storage.janitorScreenshotsDays, in: 1...365) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Screenshots older than \(config.storage.janitorScreenshotsDays) days")
                        Text("Only files in your Screenshots folder. Folders are never moved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                StringListEditor(
                    title: "Never touch anything matching these",
                    prompt: "e.g. *.dmg  or  Tax *",
                    items: $config.storage.janitorKeepPatterns
                )
            } header: {
                Text(Names.Screen.downloads)
            } footer: {
                Text("These move to the Trash, so you can always put them back — from the Undo screen or from Finder. Nothing moves until you review it and apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let backups {
                    if backups.isEmpty {
                        Text("No local iPhone/iPad backups on this Mac.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(backups) { backup in
                        HStack {
                            DataCard(symbol: "iphone", color: .blue,
                                     title: backup.deviceName,
                                     subtitle: backup.lastBackup.map {
                                         "Last backup \($0.formatted(.dateTime.month(.abbreviated).day().year()))"
                                     } ?? "Backup date unknown",
                                     trailing: ByteSize.format(backup.sizeBytes))
                            Button("Show in Finder") { IOSBackups.revealInFinder(backup) }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Sizing local device backups…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("iPhone/iPad Backups on This Mac")
            } footer: {
                Text("Report only — deleting a backup is always your manual call, in Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                SaveBar { try config.save() }
                Text("Applies on the next scheduled run — daily: \(ScheduleKit.describe(GuardControl.storageCleanLabel)); deep: \(ScheduleKit.describe(GuardControl.storageDeepLabel)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard backups == nil else { return }
            let found = await Task.detached(priority: .utility) { IOSBackups.scan() }.value
            backups = found
        }
    }

    private func toolBinding(_ tool: ToolCache, in list: Binding<[String]>) -> Binding<Bool> {
        Binding(get: { list.wrappedValue.contains(tool.rawValue) },
                set: { enabled in
                    if enabled {
                        if !list.wrappedValue.contains(tool.rawValue) {
                            list.wrappedValue.append(tool.rawValue)
                        }
                    } else {
                        list.wrappedValue.removeAll { $0 == tool.rawValue }
                    }
                })
    }
}
