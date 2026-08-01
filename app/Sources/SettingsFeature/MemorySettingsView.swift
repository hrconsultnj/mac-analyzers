import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory pane: guard tunables + the never-kill / reclaim app lists.
struct MemorySettingsView: View {
    @Environment(ConfigStore.self) private var config

    var body: some View {
        @Bindable var config = config
        Form {
            PaneHeader(symbol: "memorychip", color: .blue, title: "Memory",
                       caption: "What the guard is allowed to do, and when it should only warn you.")
            Section("Memory Guard — Limits") {
                LabeledContent("Hard RAM cap") {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(config.memory.hardCapMB) / 1024 },
                                    set: { config.memory.hardCapMB = Int(($0 * 1024).rounded()) }
                                ),
                                in: 2...24, step: 0.1
                            )
                            Text(String(format: "%.1f GB", Double(config.memory.hardCapMB) / 1024))
                                .monospacedDigit()
                                .frame(width: 58, alignment: .trailing)
                        }
                        Text("A dev process whose RESIDENT memory exceeds this is stopped — at any pressure level. 0.1 GB steps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .help("Resident (rss) = physical RAM occupied right now; compressed/swapped pages don't count. Applies only to dev tooling, never to protected processes.")

                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Stop processes over the cap", isOn: $config.memory.hardCapKill)
                    Text("Off = the guard still watches and NOTIFIES when something passes the cap, but stops nothing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Stop the biggest dev process on CRITICAL pressure", isOn: $config.memory.pressureKill)
                    Text("Off = critical memory pressure only notifies (with a forensics report) so you can act yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Memory Guard — Alerts (never stop anything)") {
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("Spike alert") {
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
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("CPU hog alert") {
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

            Section("Process Lists") {
                StringListEditor(
                    title: "Protected processes (never stopped — name fragments)",
                    prompt: "e.g. obs or my-daemon",
                    items: $config.memory.protectExtra
                )
                StringListEditor(
                    title: "Apps memory-reclaim may quit gracefully",
                    prompt: "App name as in /Applications, e.g. Docker",
                    items: $config.memory.reclaimApps
                )
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
        .formStyle(.grouped)
    }
}
