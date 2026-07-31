import SwiftUI
import AnalyzersKit

/// The MenuBarExtra(.window) dropdown: headline, readable guard events,
/// guard controls, auto-clean status, Settings/Quit footer.
public struct MenuContentView: View {
    @Environment(GuardLogStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headline

            Divider()

            sectionLabel("MEMORY GUARD")
            if store.events.isEmpty {
                Text("Quiet — no events in the last 24 h")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(store.events) { event in
                    EventRow(event: event)
                }
            }
            guardControls

            Divider()

            sectionLabel("AUTO-CLEAN")
            autoCleanRows

            Divider()

            footer
        }
        .padding(12)
        .onAppear { store.reload() }
    }

    private var headline: some View {
        HStack {
            if store.guardPaused {
                Label("Guard is paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else if store.killsToday > 0 {
                Label("\(store.killsToday) process\(store.killsToday == 1 ? "" : "es") killed today",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Label("All clear — nothing killed today", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
        }
        .font(.headline)
    }

    private var guardControls: some View {
        HStack(spacing: 12) {
            Button(store.guardPaused ? "Resume guard" : "Pause guard") {
                store.setGuardPaused(!store.guardPaused)
            }
            Button("Guard log") { GuardControl.openLog(AnalyzersPaths.guardLog) }
            if let forensics = store.latestForensics {
                Button("Forensics") { GuardControl.openLog(forensics) }
            }
            Spacer()
        }
        .controlSize(.small)
    }

    private var autoCleanRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Memory — last run \(runText(store.lastMemoryCleanRun))")
                    .font(.callout)
                Spacer()
                Button("Log") { GuardControl.openLog(AnalyzersPaths.memoryAutoCleanLog) }
                    .controlSize(.small)
            }
            HStack {
                Text("Storage — \(store.storageLastRunSummary ?? "no runs yet"), \(runText(store.lastStorageCleanRun))")
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                Button("Log") { GuardControl.openLog(AnalyzersPaths.storageAutoCleanLog) }
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                // MenuBarExtra-only apps need a real activation context or the
                // Settings window lands behind other apps: show a Dock icon
                // while Settings is open (reverted on close), activate, open.
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

struct EventRow: View {
    let event: GuardEvent

    var body: some View {
        Button {
            GuardControl.openLog(AnalyzersPaths.guardLog)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(event.date.formatted(.dateTime.hour().minute()))
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())
                Text(event.summary)
                    .font(.callout)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .help(event.raw)
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
