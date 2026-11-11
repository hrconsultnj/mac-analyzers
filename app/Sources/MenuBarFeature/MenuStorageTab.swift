import SwiftUI
import AnalyzersKit
import UIComponents

/// The Storage tab: disk usage and the storage cleanups.
extension MenuContentView {

    // MARK: - Storage tab

    @ViewBuilder var storageTab: some View {
        sectionLabel("STORAGE NOW")
        if let disk = store.disk {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    IconTile(symbol: "internaldrive.fill", color: .indigo)
                        .accessibilityHidden(true)  // decorative — "Macintosh HD" below already names it
                    Text("Macintosh HD")
                        .font(.callout.weight(.medium))
                    Text("\(disk.usedText) of \(disk.totalText) used")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(disk.freeText) free")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(disk.usedFraction > 0.9 ? .red : .primary)
                }
                CapacityBar(fraction: disk.usedFraction)
            }
        } else {
            Text("Couldn't read the boot volume.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let last = store.lastCleanDiskState {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("At last clean (\(runText(store.lastStorageCleanRun))): \(last)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .help("What the storage log recorded when the scheduled clean last ran — compare with the live bar above")
        }

        Divider()

        sectionLabel("SCHEDULED CLEANS")
        storageRow(
            title: "Daily clean",
            detail: store.storageDailySummary.map { "last: \($0)" } ?? "no runs yet",
            sub: "\(ScheduleKit.describe(GuardControl.storageCleanLabel)) — stale build caches only",
            label: GuardControl.storageCleanLabel,
            symbol: "sparkles", color: .green
        )
        storageRow(
            title: "Deep clean",
            detail: store.storageDeepSummary.map { "last: \($0)" } ?? "no runs yet",
            sub: "\(ScheduleKit.describe(GuardControl.storageDeepLabel)) — + node_modules of idle repos, idle worktrees (never main), package-manager and app caches, ALL unused Docker images, Time Machine snapshot thinning",
            label: GuardControl.storageDeepLabel,
            symbol: "wand.and.stars", color: .purple
        )

        Divider()

        // the bigger, reviewed cleans — dry-run → review → apply in the app
        sectionLabel("REVIEW & CLEAN")
        HStack(spacing: 12) {
            Button("Storage…") { SettingsOpener.open(target: "actions:storageClean") }
                .help("Preview what storage clean would remove, review, then apply")
            Button("Janitor…") { SettingsOpener.open(target: "actions:janitor") }
                .help("Stale Downloads and old screenshots — to the Trash, reviewed first")
            Button("Temp…") { SettingsOpener.open(target: "actions:tempClean") }
                .help("Idle /tmp, /var and AI-agent leftovers — to the Trash, reviewed first")
            Button("Memory…") { SettingsOpener.open(target: "actions:memoryClean") }
                .help("Close helper processes whose app already closed — reviewed first")
            Spacer()
        }
        .controlSize(.regular)

        Divider()

        HStack(spacing: 12) {
            Button("Storage log") { SettingsOpener.open(target: "log:storageClean") }
            Button("Login-items audit") { SettingsOpener.open(target: "log:loginItems") }
            Button("Spotlight audit") { SettingsOpener.open(target: "log:spotlightAudit") }
            Button("Temp & agents") { SettingsOpener.open(target: "log:tempSpace") }
            Spacer()
            Text("Last run \(runText(store.lastStorageCleanRun))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.regular)
    }

    private func storageRow(title: String, detail: String, sub: String, label: String,
                            symbol: String, color: Color) -> some View {
        HStack(alignment: .center) {
            IconTile(symbol: symbol, color: color)
                .accessibilityHidden(true)  // decorative — title below already names the row
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(title).font(.callout.weight(.medium))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Run now") { runNow(label) }
                .controlSize(.regular)
                .disabled(runNowPlan(for: label).problem != nil)
                .help(runNowPlan(for: label).problem
                      ?? "Same run the schedule does — it appears in Activity, and Stop ends it")
        }
    }

    // MARK: - Run now

    /// Whether Run now may run for one schedule, worked out once when the panel
    /// appears (`MenuContentView.onAppear`), not on every redraw. The rule is the
    /// store's (`JobStore.scheduleProblem`): the agent is installed, and its plist
    /// names the script this app would run.
    struct RunNowPlan {
        /// Why Run now must not run, in words; nil when it may.
        let problem: String?
    }

    func loadRunNowPlans() {
        for label in [GuardControl.storageCleanLabel, GuardControl.storageDeepLabel] {
            runNowPlans[label] = RunNowPlan(problem: jobs.scheduleProblem(label: label, kind: .storageClean))
        }
    }

    func runNowPlan(for label: String) -> RunNowPlan {
        runNowPlans[label] ?? RunNowPlan(problem: "Checking the schedule…")
    }

    /// Starts the schedule's own run as a tracked job. The store reads the
    /// INSTALLED plist's arguments itself, so it does exactly what the agent
    /// does; nothing is passed from here.
    private func runNow(_ label: String) {
        guard runNowPlan(for: label).problem == nil else { return }
        jobs.enqueue(JobRequest(kind: .storageClean, intent: .run), trigger: .schedule(label))
    }
}
