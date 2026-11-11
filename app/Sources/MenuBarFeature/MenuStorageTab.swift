import SwiftUI
import AnalyzersKit
import UIComponents

/// The Storage tab: disk, the scheduled cleans, and where to review each cleanup.
extension MenuContentView {

    @ViewBuilder var storageTab: some View {
        sectionLabel("Storage Now")
        if let disk = store.disk {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    IconTile(symbol: "internaldrive.fill", color: .indigo)
                        .accessibilityHidden(true)  // decorative — the name already says what it is
                    Text("Macintosh HD").font(.callout.weight(.medium))
                    Spacer()
                    Text("\(disk.freeText) free")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(disk.usedFraction > 0.9 ? .red : .primary)
                }
                ProgressView(value: disk.usedFraction)
                    .tint(disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.75 ? .orange : .accentColor)
                    .accessibilityLabel("Disk used")
                    .accessibilityValue(Text(disk.usedFraction, format: .percent.precision(.fractionLength(0))))
                Text("\(disk.usedText) of \(disk.totalText) used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("The startup disk could not be read.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let last = store.lastCleanDiskState {
            Text("At the last clean (\(runText(store.lastStorageCleanRun))): \(last)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Divider()

        sectionLabel("Scheduled Cleans")
        storageRow(title: "Daily Clean",
                   summary: store.storageDailySummary,
                   when: ScheduleKit.describe(GuardControl.storageCleanLabel),
                   what: "Stale build caches only.",
                   label: GuardControl.storageCleanLabel, symbol: "sparkles", color: .green)
        storageRow(title: "Deep Clean",
                   summary: store.storageDeepSummary,
                   when: ScheduleKit.describe(GuardControl.storageDeepLabel),
                   what: "Also the node_modules of idle projects, idle worktrees, package-manager and app caches, unused Docker images and Time Machine snapshots.",
                   label: GuardControl.storageDeepLabel, symbol: "wand.and.stars", color: .purple)

        Divider()

        sectionLabel("Review a Cleanup")
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                openButton(Names.Screen.cachesAndBuilds, target: "caches")
                openButton(Names.Screen.downloads, target: "downloads")
            }
            GridRow {
                openButton(Names.Screen.tempAndAgents, target: "temp")
                openButton(Names.Screen.memoryCleanup, target: "log:memoryClean")
            }
            GridRow {
                openButton(Names.Screen.spotlight, target: "spotlight")
                openButton(Names.Screen.loginItems, target: "loginitems")
            }
        }
    }

    /// A button that opens a screen: it names the screen and carries no ellipsis.
    private func openButton(_ title: String, target: String) -> some View {
        Button(title) { SettingsOpener.open(target: target) }
            .buttonSizing(.flexible)
    }

    private func storageRow(title: String, summary: String?, when: String, what: String,
                            label: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            IconTile(symbol: symbol, color: color)
                .accessibilityHidden(true)  // decorative — the title already names the row
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(summary.map { "Last run: \($0)." } ?? "Has not run yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(when). \(what)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Run Now") { runNow(label) }
                .disabled(runNowPlan(for: label).problem != nil)
                .help(runNowPlan(for: label).problem
                      ?? "Same run the schedule does — it appears in Activity, and Stop ends it")
        }
    }

    // MARK: - Run now

    /// Whether Run Now may run for one schedule, worked out once when the panel
    /// appears, not on every redraw. The rule is the store's
    /// (`JobStore.scheduleProblem`): the agent is installed, and its plist
    /// names the script this app would run.
    struct RunNowPlan {
        /// Why Run Now must not run, in words; nil when it may.
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
