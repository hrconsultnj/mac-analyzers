import SwiftUI
import AnalyzersKit
import UIComponents

/// Schedule pane: when each clean runs — editable, written into the installed
/// launchd plists and reloaded. The manage-agents installers preserve these
/// customizations, so a schedule set here survives reinstalls and upgrades.
struct ScheduleSettingsView: View {

    @State private var memoryCleanTime = Self.date(hour: 8, minute: 30)
    @State private var storageDailyTime = Self.date(hour: 8, minute: 0)
    @State private var deepDays = 3
    @State private var status: String?
    @State private var applying = false
    /// Only what the captions read (settings and installed schedules), not the whole How It Works load.
    @State private var facts: HowItWorksFacts?

    private static let memoryLabel = LaunchdAgentID.memoryAutoCleanDaily
    private static let storageLabel = LaunchdAgentID.storageAutoCleanDaily
    private static let deepLabel = LaunchdAgentID.storageAutoCleanDeep

    var body: some View {
        PaneScaffold(symbol: "calendar.badge.clock", color: .teal, title: Names.Screen.schedule,
                     caption: "When each clean runs. Changes apply immediately and survive upgrades.") {
            Section("Daily Cleans") {
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    LabeledContent("Memory Auto-Clean") {
                        DatePicker("", selection: $memoryCleanTime,
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Text(caption(Self.memoryLabel.rawValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    LabeledContent("Storage Daily Clean") {
                        DatePicker("", selection: $storageDailyTime,
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Text(caption(Self.storageLabel.rawValue, then: "Keep the two dailies offset so they never contend."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Deep Clean") {
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    LabeledContent("Storage Deep Clean") {
                        Stepper("every \(deepDays) day\(deepDays == 1 ? "" : "s")",
                                value: $deepDays, in: 1...14)
                    }
                    Text(caption(Self.deepLabel.rawValue, then: "Measured from load or the last run."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Always On") {
                LabeledContent("Memory Guard") {
                    Label("Runs continuously — checks \(facts?.guardEvery ?? "regularly") while the Mac is awake",
                          systemImage: "shield.lefthalf.filled")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    if let status {
                        Label(status, systemImage: status.hasPrefix("Applied")
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(status.hasPrefix("Applied") ? .green : .red)
                            .font(.callout)
                    }
                    Spacer()
                    Button(applying ? "Applying…" : "Apply Schedule") { apply() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(applying)
                }
                Text("Writes the times into macOS's scheduler and reloads it. The repo's defaults are untouched; reinstalls keep your times.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
        .task { await loadCaptions() }
    }

    // MARK: - plumbing

    /// The captions at once from the quick read, then Time Machine's permission once `sudo -n -l` answers.
    private func loadCaptions() async {
        let quick = HowItWorksFacts.read()
        facts = quick
        guard quick.schedules.contains(where: { $0.installed && $0.thinsSnapshots }) else { return }
        let allowed = await TimeMachinePermission.isAllowed()
        facts?.timeMachinePermission = allowed
    }

    /// A job's caption; the sentence after it only when the job is installed (nothing more to say about one that is not).
    private func caption(_ label: String, then extra: String? = nil) -> String {
        guard let facts else { return "" }
        let text = facts.jobCaption(label)
        guard let extra, facts.schedule(label)?.installed == true else { return text }
        return text + " " + extra
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    private func load() {
        if case .daily(let h, let m)? = ScheduleKit.schedule(for: Self.memoryLabel.rawValue) {
            memoryCleanTime = Self.date(hour: h, minute: m)
        }
        if case .daily(let h, let m)? = ScheduleKit.schedule(for: Self.storageLabel.rawValue) {
            storageDailyTime = Self.date(hour: h, minute: m)
        }
        if case .interval(let days)? = ScheduleKit.schedule(for: Self.deepLabel.rawValue) {
            deepDays = days
        }
    }

    private func apply() {
        let cal = Calendar.current
        let m = cal.dateComponents([.hour, .minute], from: memoryCleanTime)
        let s = cal.dateComponents([.hour, .minute], from: storageDailyTime)
        let changes: [(ScheduleKit.Schedule, String)] = [
            (.daily(hour: m.hour ?? 8, minute: m.minute ?? 30), Self.memoryLabel.rawValue),
            (.daily(hour: s.hour ?? 8, minute: s.minute ?? 0), Self.storageLabel.rawValue),
            (.interval(days: deepDays), Self.deepLabel.rawValue),
        ]
        applying = true
        status = nil
        Task {
            // reloading an agent can take a few seconds; never on the main thread
            let outcomes = await Task.detached(priority: .userInitiated) {
                changes.map { ScheduleKit.apply($0.0, to: $0.1) }
            }.value
            let failures: [String] = outcomes.compactMap {
                if case .failed(let why) = $0 { why } else { nil }
            }
            status = failures.isEmpty
                ? "Applied — agents reloaded with the new times."
                : failures.joined(separator: "\n")
            applying = false
        }
    }
}
