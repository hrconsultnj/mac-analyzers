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
                .disabled(scheduledArguments(for: label) == nil)
                .help(scheduledArguments(for: label) == nil
                      ? "This schedule isn't installed on this Mac"
                      : "Same run the schedule does — it appears in Activity, and Stop ends it")
        }
    }

    // MARK: - Run now

    /// Starts the schedule's own run as a tracked job: the arguments are read
    /// from the INSTALLED launchd plist, so it does exactly what the agent
    /// does, no more. Triggered as `.schedule(label)`; the kernel refuses a
    /// cleaner run by hand any other way.
    private func runNow(_ label: String) {
        guard let arguments = scheduledArguments(for: label) else { return }
        jobs.enqueue(JobRequest(kind: .storageClean, intent: .run,
                                options: JobOptions(scheduleArguments: arguments)),
                     trigger: .schedule(label))
    }

    /// What the plist passes to the script: `ProgramArguments` after the script
    /// path (the entry before it is the runner). nil when the agent is not installed.
    private func scheduledArguments(for label: String) -> [String]? {
        let plist = AnalyzersPaths.home.appending(path: "Library/LaunchAgents/\(label).plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let program = dict["ProgramArguments"] as? [String],
              let script = program.firstIndex(where: { $0.hasSuffix(".sh") })
        else { return nil }
        return Array(program[(script + 1)...])
    }
}
