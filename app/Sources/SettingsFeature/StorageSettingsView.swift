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
                Text("Opt-in per tool. Everything here is redownloadable or rebuildable cache — sources and state are never in scope. Sizes show in every dry run; cleaning happens on apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                SaveBar { try config.save() }
                Text("Applies on the next scheduled run (daily 8:00 AM / deep every 3 days).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
    var id: String { rawValue }

    var title: String {
        switch self {
        case .brew: "Homebrew downloads"
        case .pip: "pip cache"
        case .uv: "uv cache"
        case .cargo: "Cargo registry cache"
        case .gradle: "Gradle caches"
        case .deriveddata: "Xcode DerivedData"
        }
    }

    var detail: String {
        switch self {
        case .brew: "brew cleanup --prune=all — old bottles and downloads."
        case .pip: "pip3 cache purge — wheel downloads."
        case .uv: "uv cache prune — unreferenced entries only."
        case .cargo: "Removes ~/.cargo/registry/cache — re-fetched on demand."
        case .gradle: "Removes ~/.gradle/caches — next build re-downloads."
        case .deriveddata: "Empties DerivedData — Xcode rebuilds indexes."
        }
    }
}
