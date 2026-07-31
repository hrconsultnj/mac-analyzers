import SwiftUI
import AnalyzersKit

/// Memory tab: guard tunables + the never-kill / reclaim app lists.
struct MemorySettingsView: View {
    @Environment(ConfigStore.self) private var config

    var body: some View {
        @Bindable var config = config
        Form {
            Section("Memory guard") {
                LabeledContent("Hard RAM cap") {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(config.memory.hardCapMB) / 1024 },
                                    set: { config.memory.hardCapMB = Int($0 * 1024) }
                                ),
                                in: 2...24, step: 0.5
                            )
                            Text(String(format: "%.1f GB", Double(config.memory.hardCapMB) / 1024))
                                .monospacedDigit()
                                .frame(width: 58, alignment: .trailing)
                        }
                        Text("A dev process whose RESIDENT memory exceeds this is killed — at any pressure level.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .help("Resident (rss) = physical RAM occupied right now; compressed/swapped pages don't count. Applies only to dev tooling, never to protected processes.")
                LabeledContent("Spike alert") {
                    HStack {
                        Stepper("+\(config.memory.spikeMB) MB per tick",
                                value: $config.memory.spikeMB, in: 100...2000, step: 50)
                        Stepper("once above \(config.memory.spikeMinMB) MB",
                                value: $config.memory.spikeMinMB, in: 256...8192, step: 256)
                    }
                }
                .help("Notification-only: a process growing faster than this per 15-second tick (once past the floor) is flagged as a runaway. Nothing is killed for spiking.")
                LabeledContent("CPU hog alert") {
                    HStack {
                        Stepper("\(config.memory.cpuHogPct)% CPU",
                                value: $config.memory.cpuHogPct, in: 50...800, step: 25)
                        Stepper("for \(config.memory.cpuHogTicks) ticks",
                                value: $config.memory.cpuHogTicks, in: 1...20)
                    }
                }
                .help("Notification-only: sustained CPU above this for N consecutive ticks. CPU is never a kill reason.")
            }

            Section {
                StringListEditor(
                    title: "Protected processes (never killed — regex fragments)",
                    prompt: "e.g. obs or my-daemon",
                    items: $config.memory.protectExtra
                )
                StringListEditor(
                    title: "Apps memory-reclaim may quit gracefully",
                    prompt: "App name as in /Applications, e.g. Docker",
                    items: $config.memory.reclaimApps
                )
            }

            Section("How the guard decides") {
                DisclosureGroup("What is measured, and when a process gets killed") {
                    VStack(alignment: .leading, spacing: 8) {
                        explainRow("gauge.with.needle",
                            "Measures resident RAM (rss): the physical memory a process occupies right now. Activity Monitor's \"Memory\" column also counts compressed/swapped pages, so a process can show 7+ GB there while its resident size sits under the cap — that is why a big process can survive when pressure is low. VRAM/GPU memory is never considered.")
                        explainRow("scope",
                            "Only dev tooling is ever touchable: node, npm, bun, tsx, deno, next/vite/webpack/turbo dev servers, vitest/jest, Playwright and headless browsers. Everything else — and anything on your protected list — is never killed.")
                        explainRow("1.circle",
                            "Hard cap: every 15 s the single biggest touchable process is checked; if its resident size exceeds the cap it is killed at ANY pressure level (60 s cooldown between kills), with a forensics report written first.")
                        explainRow("2.circle",
                            "Spikes: growth beyond the per-tick threshold (once the process is past the floor) logs and notifies — no kill.")
                        explainRow("3.circle",
                            "System pressure: WARNING notifies with the top consumers; CRITICAL writes forensics and kills the biggest touchable process if it holds over 500 MB.")
                        explainRow("4.circle",
                            "CPU hogs: sustained high CPU only ever notifies. CPU is never a kill reason.")
                    }
                    .padding(.vertical, 4)
                }
                .font(.callout)
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

    private func explainRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
