import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The Monitor tab: who is using memory, from the same census, names and
/// footprint numbers as Monitor — grouped by app, biggest first, no size floor.
extension MenuContentView {

    @ViewBuilder var monitorTab: some View {
        HStack {
            pressureRow
            Spacer()
            Picker("Refresh", selection: $monitorRefresh) {
                Text("Every 5 Seconds").tag(5)
                Text("Every 15 Seconds").tag(15)
                Text("Every Minute").tag(60)
                Text("Never").tag(0)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("How often this list refreshes while open")
        }
        .task(id: monitorRefresh) { await refreshCensus() }

        sectionLabel("Using the Most Memory")
        if let panel {
            ForEach(panel.processes) { row in
                ProcessGroupRow(row: row, reload: { Task { await refreshCensus(once: true) } })
            }
            MenuRowButton(action: { SettingsOpener.open(target: "monitor") }) {
                HStack {
                    Text("\(panel.totalGroups - panel.processes.count) more in \(Names.Screen.monitor)")
                        .font(.callout)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)  // decorative disclosure arrow
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading every process…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One census, off the main actor, then again every `monitorRefresh`
    /// seconds while this tab stays open (the task is cancelled when it does not).
    func refreshCensus(once: Bool = false) async {
        repeat {
            let taken = await Task.detached(priority: .userInitiated) {
                MenuPanelModel(census: MemoryCensus.take())
            }.value
            panel = taken
            guard !once, monitorRefresh > 0 else { return }
            try? await Task.sleep(for: .seconds(Double(monitorRefresh)))
        } while !Task.isCancelled && !once
    }
}

/// One app, tool or service: its icon, name, what it is made of, the memory it
/// holds in total, and one Quit (or Stop) for the whole group. Part of macOS:
/// the same row with a lock where the button would be, so the layout never changes.
struct ProcessGroupRow: View {
    let row: MenuPanelModel.ProcessRow
    let reload: () -> Void
    @State private var working = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // the name side opens Monitor: the place to see what a group is made of and to stop a tool
            MenuRowButton(action: { SettingsOpener.open(target: "monitor") }) {
                HStack(alignment: .center, spacing: 8) {
                    icon.frame(width: 20, height: 20).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).font(.callout.weight(.medium))
                        if let detail = row.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        if let reason = lockedReason {
                            Text(reason).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(row.sizeText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            if row.canQuit && row.isApp {
                // an app: ⌘Q, which still asks about unsaved work
                Button("Quit") {
                    working = true
                    GuardControl.quit(row.group.quit)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        reload()
                        working = false
                    }
                }
                .disabled(working)
                .help("Quit \(row.name) and its helpers, like ⌘Q — save prompts still appear")
            } else {
                // part of macOS, or a command-line tool group. Stopping a tool group from here could end
                // every live coding-agent session at once, so it is done in Monitor, which protects
                // live sessions; the panel offers no Stop for it.
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .help(row.canQuit ? "Stop it from \(Names.Screen.monitor), which protects live coding sessions"
                                      : "Part of macOS — not something to quit from here")
                    .accessibilityLabel(row.canQuit ? "Stopped from Monitor only" : "Part of macOS, not quittable here")
            }
        }
        .padding(.vertical, 2)
    }

    /// Said in words under the name, because a padlock alone explains nothing in a panel.
    private var lockedReason: String? {
        if row.canQuit && row.isApp { return nil }
        return row.canQuit ? "Stop it in \(Names.Screen.monitor), which protects live coding sessions"
                           : "Part of macOS"
    }

    @ViewBuilder private var icon: some View {
        if row.category == .apps,
           let app = NSRunningApplication(processIdentifier: pid_t(row.group.lead.pid)),
           let image = app.icon {
            Image(nsImage: image).resizable()
        } else {
            IconTile(symbol: row.category == .tools ? "hammer.fill" : "gearshape.fill",
                     color: row.category == .tools ? .blue : .gray, side: 20)
        }
    }
}
