import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory pane: guard tunables + the never-kill / reclaim app lists.
struct MemorySettingsView: View {
    @Environment(ConfigStore.self) private var config
    @State private var processListTab: ProcessListTab = .protected

    private enum ProcessListTab: String, CaseIterable {
        case protected = "Protected", reclaim = "Reclaim"
    }

    var body: some View {
        @Bindable var config = config
        PaneScaffold(symbol: "memorychip", color: .blue, title: Names.Screen.memorySettings,
                     caption: "What the guard is allowed to do, and when it should only warn you.") {
            Section("Memory Guard — Limits") {
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    Slider(
                        value: Binding(
                            get: { Double(config.memory.hardCapMB) / 1024 },
                            set: { config.memory.hardCapMB = Int(($0 * 1024).rounded()) }
                        ),
                        in: 2...24, step: 0.1
                    ) {
                        Text("Hard RAM Cap")
                    } minimumValueLabel: {
                        Text("2 GB")
                    } maximumValueLabel: {
                        Text("24 GB")
                    }
                    Text("Now \(String(format: "%.1f GB", Double(config.memory.hardCapMB) / 1024)). A dev process using more memory than this is stopped — at any pressure level. 0.1 GB steps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help("Physical memory in use right now; dev tools only, never protected processes")

                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    Toggle("Stop processes over the cap", isOn: $config.memory.hardCapKill)
                    Text("Off = the guard still watches and notifies when something passes the cap, but stops nothing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    Toggle("Stop the biggest dev process at critical pressure", isOn: $config.memory.pressureKill)
                    Text("Off = critical memory pressure only notifies (with a crisis report) so you can act yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Memory Guard — Alerts (Never Stop Anything)") {
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    LabeledContent("Spike Alert") {
                        HStack {
                            Stepper("+\(config.memory.spikeMB) MB per tick",
                                    value: $config.memory.spikeMB, in: 100...2000, step: 50)
                            Stepper("once above \(config.memory.spikeMinMB) MB",
                                    value: $config.memory.spikeMinMB, in: 256...8192, step: 256)
                        }
                    }
                    Text("Notifies when a process grows faster than this per 15-second check, once it's past the floor size.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    LabeledContent("CPU Hog Alert") {
                        HStack {
                            Stepper("\(config.memory.cpuHogPct)% CPU",
                                    value: $config.memory.cpuHogPct, in: 50...800, step: 25)
                            Stepper("for \(config.memory.cpuHogTicks) checks",
                                    value: $config.memory.cpuHogTicks, in: 1...20)
                        }
                    }
                    Text("Notifies about sustained CPU use. CPU is never a reason to stop anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                // a choice between two lists, not categories: a segmented picker in the form
                Picker("List", selection: $processListTab) {
                    ForEach(ProcessListTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(processListTab == .protected
                     ? "Never stopped by the guard or the reapers — matched against process names."
                     : "Quit gracefully (same as ⌘Q, save dialogs appear) when memory-reclaim runs with apps enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                switch processListTab {
                case .protected:
                    AppListEditor(
                        title: "Protected processes",
                        mode: .processFragments,
                        items: $config.memory.protectExtra,
                        height: 220
                    )
                case .reclaim:
                    AppListEditor(
                        title: "Reclaim may quit",
                        mode: .installedApps,
                        items: $config.memory.reclaimApps,
                        height: 220
                    )
                }
            } header: {
                Text("Process Lists")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Section {
                SaveBar {
                    try config.save()
                    GuardControl.restartGuard()
                }
                Text("Saving restarts the memory guard so new limits apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
