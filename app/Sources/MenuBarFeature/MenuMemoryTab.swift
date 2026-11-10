import SwiftUI
import AnalyzersKit
import UIComponents

/// The Memory tab: headline, live strip and recent guard events.
extension MenuContentView {

    // MARK: - Memory tab

    @ViewBuilder var memoryTab: some View {
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

    var pressureColor: Color {
        switch store.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    /// Paired with pressureColor so the state has a shape, not just a tint —
    /// colour alone doesn't reach a colourblind user.
    var pressureSymbol: String {
        switch store.pressure {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
