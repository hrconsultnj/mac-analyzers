import SwiftUI
import AnalyzersKit

/// The MenuBarExtra(.window) dropdown: Memory | Storage tabs, live system
/// facts, two-line human-readable events, controls, shared footer.
public struct MenuContentView: View {
    @Environment(GuardLogStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @State private var tab: Tab = .memory

    enum Tab: String, CaseIterable { case memory = "Memory", storage = "Storage" }

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
                    .controlSize(.small)
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

        HStack(spacing: 12) {
            Button(store.guardPaused ? "Resume guard" : "Pause guard") {
                store.setGuardPaused(!store.guardPaused)
            }
            Button("Guard log") { GuardControl.openLog(AnalyzersPaths.guardLog) }
            if let forensics = store.latestForensics {
                Button("Forensics") { GuardControl.openLog(forensics) }
            }
            Spacer()
            Text("Reaper: \(runText(store.lastMemoryCleanRun))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Daily 8:30 AM reaper for orphaned dev/AI servers — memory-auto-clean log")
        }
        .controlSize(.small)
    }

    private var headline: some View {
        Group {
            if store.guardPaused {
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
            Circle()
                .fill(pressureColor)
                .frame(width: 8, height: 8)
            Text("Memory pressure: \(store.pressure.label)")
                .font(.callout)
                .foregroundStyle(store.pressure == .normal ? .secondary : .primary)
            Spacer()
        }
        if !store.topProcesses.isEmpty {
            sectionLabel("BIGGEST DEV PROCESSES NOW")
            ForEach(store.topProcesses) { proc in
                HStack(spacing: 6) {
                    Text(proc.residentText)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(proc.residentMB > 4096 ? .orange : .secondary)
                        .frame(width: 54, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(proc.friendlyName).font(.callout)
                        if proc.friendlyName != proc.rawName {
                            Text("\(proc.rawName.prefix(52)) · pid \(proc.pid)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var pressureColor: Color {
        switch store.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    // MARK: - Storage tab

    @ViewBuilder private var storageTab: some View {
        sectionLabel("SCHEDULED CLEANS")
        storageRow(
            title: "Daily clean",
            detail: store.storageDailySummary.map { "last: \($0)" } ?? "no runs yet",
            sub: "Every day 8:00 AM — stale build caches only",
            label: GuardControl.storageCleanLabel
        )
        storageRow(
            title: "Deep clean",
            detail: store.storageDeepSummary.map { "last: \($0)" } ?? "no runs yet",
            sub: "Every 3 days — + node_modules of idle repos, Docker, TM snapshots",
            label: GuardControl.storageDeepLabel
        )

        Divider()

        HStack(spacing: 12) {
            Button("Storage log") { GuardControl.openLog(AnalyzersPaths.storageAutoCleanLog) }
            Button("Login-items audit") { GuardControl.openLog(AnalyzersPaths.loginItemsAuditLog) }
            Spacer()
            Text("Last run \(runText(store.lastStorageCleanRun))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
    }

    private func storageRow(title: String, detail: String, sub: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(title).font(.callout.weight(.medium))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Text(sub).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Run now") { GuardControl.runNow(label) }
                .controlSize(.small)
                .help("Same run the schedule would do — dry-run-safe rules apply")
        }
    }

    // MARK: - shared

    private var footer: some View {
        HStack {
            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            Spacer()
            Button {
                GuardControl.restartApp()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Restart this app only — nothing else is touched")
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
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

/// Two-line event row: friendly what-happened on top, raw identity +
/// mechanics + time underneath. Click opens the guard log.
struct EventRow: View {
    let event: GuardEvent

    var body: some View {
        Button {
            GuardControl.openLog(AnalyzersPaths.guardLog)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.caption)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.callout)
                        .foregroundStyle(color)
                        .lineLimit(1)
                    Text(subtitleWithTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .help(event.raw)
    }

    private var subtitleWithTime: String {
        let time = event.date.formatted(.dateTime.hour().minute())
        return event.subtitle.isEmpty ? time : "\(event.subtitle) · \(time)"
    }

    private var symbol: String {
        switch event.kind {
        case .killed: "xmark.octagon.fill"
        case .spike: "arrow.up.right"
        case .warning: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch event.kind {
        case .killed: .red
        case .spike, .warning: .orange
        }
    }
}
