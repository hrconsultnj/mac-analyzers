import SwiftUI
import AnalyzersKit
import UIComponents

/// The Memory tab: the guard's state, recent events and the guard's actions.
extension MenuContentView {

    @ViewBuilder var memoryTab: some View {
        HStack {
            guardState
            Spacer()
            if store.killsToday > 0 || !store.events.isEmpty {
                Button("Clear") { store.clearStats() }
                    .help("Resets the badge and this list; the guard log keeps the history")
            }
        }

        pressureRow

        MenuMemoryBlock()

        Divider()

        if !store.ruleLines.isEmpty {
            sectionLabel("Rules Today")
            ForEach(store.ruleLines) { line in
                MenuRowButton(action: { SettingsOpener.open(target: line.target) }) {
                    Text(line.text).font(.callout)
                }
            }
        }

        sectionLabel("Recent Events")
        let rows = OverviewModel.eventRows(store.events, limit: 6)
        if rows.isEmpty {
            Text("Quiet — nothing in the last 24 hours.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(rows) { MenuEventRow(row: $0) }
        }

        if let pauseError {
            Label(pauseError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Button(store.guardPaused ? "Resume Guard" : "Pause Guard") {
                do {
                    try store.setGuardPaused(!store.guardPaused)
                    pauseError = nil
                } catch {
                    pauseError = error.localizedDescription
                }
            }
            Button(Names.Screen.memoryGuard) { SettingsOpener.open(target: "log:guardLog") }
            if store.latestForensics != nil {
                Button(Names.crisisReports) { SettingsOpener.open(target: "log:forensics") }
            }
        }
        Text("\(Names.Screen.memoryCleanup) last ran \(runText(store.lastMemoryCleanRun)).")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Three honest states from what launchd reports, then today's count.
    private var guardState: some View {
        Group {
            if let engine = store.engine, !engine.isFullyInstalled {
                Label("Guard not set up", systemImage: "shield.slash").foregroundStyle(.orange)
            } else if let engine = store.engine, !engine.guardPaused, !engine.guardProcessRunning {
                Label("Guard not running", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if store.guardPaused {
                Label("Guard is paused", systemImage: "pause.circle.fill").foregroundStyle(.orange)
            } else if store.killsToday > 0 {
                Label("\(store.killsToday) \(store.killsToday == 1 ? "process" : "processes") stopped today",
                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else {
                Label("No processes stopped today", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .font(.headline)
    }

    var pressureRow: some View {
        Label {
            Text("Memory Pressure: \(store.pressure.label)")
                .foregroundStyle(store.pressure == .normal ? .secondary : .primary)
        } icon: {
            Image(systemName: pressureSymbol).foregroundStyle(pressureColor)
        }
        .font(.callout)
    }

    var pressureColor: Color {
        switch store.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    /// Paired with the colour so the state has a shape, not just a tint.
    var pressureSymbol: String {
        switch store.pressure {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
