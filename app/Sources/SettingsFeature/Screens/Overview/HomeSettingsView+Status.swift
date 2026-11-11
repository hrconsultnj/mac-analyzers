import SwiftUI
import AnalyzersKit
import UIComponents

/// The status tiles: memory pressure, the guard and the disk.
extension HomeSettingsView {

    // MARK: - status tiles

    var statusSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                      spacing: 10) {
                statTile(symbol: "memorychip", color: pressureColor,
                         value: store.pressure.label,
                         label: "Memory Pressure", target: "monitor")
                statTile(symbol: guardSymbol, color: guardColor,
                         value: store.engine?.summary ?? "Checking…",
                         label: guardLabel,
                         target: "guard")
                statTile(symbol: diskSymbol, color: diskColor,
                         value: store.disk.map { "\($0.freeText) free" } ?? "—",
                         label: runway.map { "runway \($0.text) at current pace" }
                             ?? store.disk.map { "of \($0.totalText) used \($0.usedText)" }
                             ?? "Disk",
                         target: "storage")
            }
            .padding(.vertical, 2)
        }
    }

    /// Three honest states, from what launchd actually reports — the tile
    /// used to show green "Active" purely because a pause file was absent,
    /// so a Mac with nothing installed looked protected.
    private var guardSymbol: String {
        guard let engine = store.engine else { return "shield.lefthalf.filled" }
        if !engine.isFullyInstalled { return "shield.slash" }
        if engine.guardPaused { return "pause.circle.fill" }
        if !engine.guardProcessRunning { return "exclamationmark.triangle.fill" }
        return "shield.lefthalf.filled"
    }

    private var guardColor: Color {
        guard let engine = store.engine else { return .secondary }
        if !engine.isFullyInstalled { return .orange }
        if engine.guardPaused || !engine.guardProcessRunning { return .orange }
        return .green
    }

    private var guardLabel: String {
        guard let engine = store.engine else { return "Guard" }
        if !engine.isFullyInstalled { return "Guard · not set up yet" }
        if engine.guardPaused { return "Guard · taking no action" }
        if !engine.guardProcessRunning { return "Guard · loaded but not running" }
        return store.killsToday == 1 ? "Guard · 1 stop today"
                                     : "Guard · \(store.killsToday) stops today"
    }

    private var pressureColor: Color {
        switch store.pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private var diskColor: Color {
        guard let disk = store.disk else { return .indigo }
        return disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.75 ? .orange : .indigo
    }

    /// Getting-full is conveyed by colour on this tile, but colour alone
    /// isn't accessible — a differing symbol is the second channel.
    private var diskSymbol: String {
        guard let disk = store.disk else { return "internaldrive.fill" }
        return disk.usedFraction > 0.75 ? "exclamationmark.triangle.fill" : "internaldrive.fill"
    }

    private func statTile(symbol: String, color: Color, value: String,
                          label: String, target: String) -> some View {
        Button {
            openPane(target)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.body)
                    .accessibilityHidden(true) // decorative — value + label below already say this
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
