import SwiftUI
import AnalyzersKit
import UIComponents

/// The MenuBarExtra(.window) dropdown: Memory | Storage tabs, live system
/// facts, two-line human-readable events, controls, shared footer.
public struct MenuContentView: View {
    @Environment(GuardLogStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab = .memory
    @AppStorage("monitorRefreshSeconds") private var monitorRefresh = 15
    @State private var latestVersion: String?
    @State private var pauseError: String?

    enum Tab: String, CaseIterable {
        case memory = "Memory", monitor = "Monitor", storage = "Storage"
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .memory: memoryTab
            case .monitor: monitorTab
            case .storage: storageTab
            }

            Divider()
            footer
        }
        .padding(12)
        .onAppear { store.reload() }
    }

    // MARK: - Memory tab

    @ViewBuilder private var memoryTab: some View {
        HStack {
            headline
            Spacer()
            if store.killsToday > 0 || !store.events.isEmpty {
                Button("Clear") { store.clearStats() }
                    .controlSize(.regular)
                    .help("Resets the badge and this list. The guard log keeps the full history — nothing is deleted.")
            }
        }

        liveStrip

        Divider()

        sectionLabel("RECENT EVENTS")
        if store.events.isEmpty {
            Text("Quiet — nothing in the last 24 h")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ForEach(store.events) { event in
                EventRow(event: event)
            }
        }

        if let pauseError {
            Label(pauseError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 12) {
            Button(store.guardPaused ? "Resume guard" : "Pause guard") {
                do {
                    try store.setGuardPaused(!store.guardPaused)
                    pauseError = nil
                } catch {
                    pauseError = error.localizedDescription
                }
            }
            Button("Guard log") { SettingsOpener.open(target: "log:guardLog") }
            if store.latestForensics != nil {
                Button("Forensics") { SettingsOpener.open(target: "log:forensics") }
            }
            Spacer()
            Text("Reaper: \(runText(store.lastMemoryCleanRun))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Closes helper processes whose app already closed. \(ScheduleKit.describe("com.mac-analyzers.memory-autoclean.daily")) — see the memory-auto-clean log")
        }
        .controlSize(.regular)
    }

    private var headline: some View {
        Group {
            if let engine = store.engine, !engine.isFullyInstalled {
                Label("Guard not set up", systemImage: "shield.slash")
                    .foregroundStyle(.orange)
            } else if let engine = store.engine,
                      !engine.guardPaused, !engine.guardProcessRunning {
                Label("Guard not running", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if store.guardPaused {
                Label("Guard is paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else if store.killsToday > 0 {
                Label("\(store.killsToday) process\(store.killsToday == 1 ? "" : "es") stopped today",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Label("All clear today", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.headline)
    }

    /// What the guard sees right now: pressure + the biggest dev processes.
    @ViewBuilder private var liveStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: pressureSymbol)
                .foregroundStyle(pressureColor)
                .font(.caption2)
                .accessibilityHidden(true)  // decorative — the label text already says the state
            Text("Memory pressure: \(store.pressure.label)")
                .font(.callout)
                .foregroundStyle(store.pressure == .normal ? .secondary : .primary)
            Spacer()
        }
        if !store.topProcesses.isEmpty {
            sectionLabel("BIGGEST DEV PROCESSES NOW")
            ForEach(store.topProcesses) { proc in
                ProcessRow(proc: proc) { store.reload() }
            }
            Text("Full list — including apps and helpers — in the Monitor tab.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var pressureColor: Color {
        switch store.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    /// Paired with pressureColor so the state has a shape, not just a tint —
    /// colour alone doesn't reach a colourblind user.
    private var pressureSymbol: String {
        switch store.pressure {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    // MARK: - Monitor tab

    /// Mini live monitor: what the guard can see and act on — resident RAM
    /// across ALL big processes (apps, helpers, dev tools), stoppable per row.
    @ViewBuilder private var monitorTab: some View {
        HStack(spacing: 6) {
            Image(systemName: pressureSymbol)
                .foregroundStyle(pressureColor)
                .font(.caption2)
                .accessibilityHidden(true)  // decorative — the label text already says the state
            Text("Pressure: \(store.pressure.label)")
                .font(.callout)
                .foregroundStyle(store.pressure == .normal ? .secondary : .primary)
            Spacer()
            // Activity-Monitor-style update frequency
            Picker("", selection: $monitorRefresh) {
                Text("5s").tag(5)
                Text("15s").tag(15)
                Text("60s").tag(60)
                Text("Off").tag(0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
            .help("How often this list refreshes while open (like Activity Monitor's update frequency)")
        }
        .task(id: monitorRefresh) {
            guard monitorRefresh > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(monitorRefresh)))
                store.reload()
            }
        }

        // same family grouping as the Monitor pane — one row per app,
        // helpers rolled underneath, expandable in place
        if !store.monitorGroups.isEmpty {
            sectionLabel("PROCESSES")
            ForEach(store.monitorGroups) { group in
                if group.children.isEmpty {
                    ProcessRow(proc: group.parent) { store.reload() }
                } else {
                    DisclosureGroup {
                        ProcessRow(proc: group.parent) { store.reload() }
                        ForEach(group.children) { child in
                            ProcessRow(proc: child) { store.reload() }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Group {
                                if let app = NSRunningApplication(processIdentifier: pid_t(group.parent.pid)),
                                   let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                                } else {
                                    IconTile(symbol: "square.stack.3d.up.fill", color: .orange)
                                }
                            }
                            .accessibilityHidden(true)  // decorative — friendlyName below already names it
                            Text(group.parent.friendlyName)
                                .font(.callout.weight(.medium))
                            Text("\(group.children.count) helpers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            Text(group.totalText)
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        if store.monitorGroups.isEmpty {
            Text("No process is holding more than 256 MB right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Text("Sizes show memory in use right now — the same number the guard acts on. Stop sends the same polite quit request Activity Monitor's Quit does.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Storage tab

    @ViewBuilder private var storageTab: some View {
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
            sub: "\(ScheduleKit.describe(GuardControl.storageDeepLabel)) — + node_modules of idle repos, package-manager caches, ALL unused Docker images, Time Machine snapshot thinning",
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
            Button("Memory…") { SettingsOpener.open(target: "actions:memoryClean") }
                .help("Close helper processes whose app already closed — reviewed first")
            Spacer()
        }
        .controlSize(.regular)

        Divider()

        HStack(spacing: 12) {
            Button("Storage log") { SettingsOpener.open(target: "log:storageClean") }
            Button("Login-items audit") { SettingsOpener.open(target: "log:loginItems") }
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
            Button("Run now") { GuardControl.runNow(label) }
                .controlSize(.regular)
                .help("Same run the schedule would do — dry-run-safe rules apply")
        }
    }

    // MARK: - shared

    private var footer: some View {
        HStack {
            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            if let latest = latestVersion,
               UpdateChecker.isNewer(latest, than: UpdateChecker.installedVersion) {
                Button("Upgrade to v\(latest)") { GuardControl.runUpgrade() }
                    .buttonStyle(.borderedProminent)
                    .help("Runs upgrade.command in Terminal — pull, rebuild, relaunch; settings untouched")
            } else {
                Text("v\(UpdateChecker.installedVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                GuardControl.restartApp()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Restart this app only — nothing else is touched")
            .accessibilityLabel("Restart app")
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.regular)
        .task { latestVersion = await UpdateChecker.latestVersion() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func runText(_ date: Date?) -> String {
        guard let date else { return "never" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
