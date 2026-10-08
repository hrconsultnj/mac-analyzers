import SwiftUI
import AnalyzersKit
import UIComponents

/// Storage pane: auto-clean scope lists + recordings folder.
struct StorageSettingsView: View {
    @Environment(ConfigStore.self) private var config
    @State private var backups: [IOSBackup]?

    var body: some View {
        @Bindable var config = config
        PaneScaffold(symbol: "internaldrive.fill", color: .indigo, title: "Storage",
                     caption: "What the SCHEDULED cleans may touch — build output and caches only, all of it regenerable. The Downloads janitor is separate: it moves old files to the Trash, after you review them, and you can undo it.") {
            Section("Storage auto-clean") {
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
                LabeledContent("Recordings folder") {
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
                Text("Tool caches (expansion pack)")
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
                             ? "Finished worktrees: off"
                             : "Remove finished worktrees after \(config.storage.worktreeIdleDays) idle \(config.storage.worktreeIdleDays == 1 ? "day" : "days")")
                        Text("Worktrees whose work is already merged into your current checkout or a base branch (main, development — squash merges count) are removed with git; the branch stays. Never: unmerged work, uncommitted or untracked files, ignored files that aren't build output (an .env, a local database, a key), locked worktrees, or one a terminal or agent session is sitting in. Deep clean only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Code projects")
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
                Text("Downloads janitor")
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
                Text("iPhone/iPad backups on this Mac")
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

/// The expansion-pack cache ids — must match storage-auto-clean.sh's
/// tool_cache registrations.
enum ToolCache: String, CaseIterable, Identifiable {
    case brew, pip, uv, cargo, gradle, deriveddata
    case appcaches, gomod, bun, cipd, simulators, avd, aerials
    var id: String { rawValue }

    var title: String {
        switch self {
        case .brew: "Homebrew downloads"
        case .pip: "pip cache"
        case .uv: "uv cache"
        case .cargo: "Cargo registry cache"
        case .gradle: "Gradle caches"
        case .deriveddata: "Xcode DerivedData"
        case .appcaches: "App caches (~/Library/Caches)"
        case .gomod: "Go module cache"
        case .bun: "Bun install cache"
        case .cipd: "CIPD cache"
        case .simulators: "Unused simulators"
        case .avd: "Android emulator snapshots"
        case .aerials: "Downloaded aerial wallpapers"
        }
    }

    var detail: String {
        switch self {
        case .brew: "brew cleanup --prune=all -s — old versions, bottles and downloads."
        case .pip: "pip3 cache purge — wheel downloads."
        case .uv: "uv cache prune — unreferenced entries only."
        case .cargo: "Removes ~/.cargo/registry cache and sources — re-fetched on demand."
        case .gradle: "Removes ~/.gradle/caches — next build re-downloads."
        case .deriveddata: "Empties DerivedData — Xcode rebuilds indexes."
        case .appcaches: "Every app's cache folder except macOS system caches, your protect list, and anything written in the last hour. Apps rebuild them."
        case .gomod: "go clean -modcache — modules re-download on the next build."
        case .bun: "Removes ~/.bun/install/cache — re-downloaded on install."
        case .cipd: "Removes ~/.cipd-cache-dir — toolchain downloads, re-fetched on demand."
        case .simulators: "Simulator runtimes never booted (installed 7+ days ago) and devices whose runtime is gone. Xcode re-downloads on demand."
        case .avd: "Quick-boot snapshots, only while no emulator runs — the next boot is a cold boot."
        case .aerials: "Aerial videos not shown in 14 days — macOS re-downloads the one you use."
        }
    }
}
