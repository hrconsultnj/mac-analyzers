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
/// holds in total, and one Quit (or Stop) for the whole group.
///
/// The row signals nothing itself. Quit and Stop ask `MemoryStop` for a plan from the live process table
/// when pressed (`PanelStop`); a refusal is said on the row in the sentence the plan gives; a plan that needs
/// the person's yes is confirmed right here with the plan's own title, detail and action word before
/// anything is sent; and a program that did not stop is never forced from here: the row offers to open
/// Monitor on it, where Force Stop has its own confirmation. A row that cannot be stopped has a lock
/// where the button would be, so the layout never changes, and says why under its name.
struct ProcessGroupRow: View {
    let row: MenuPanelModel.ProcessRow
    let reload: () -> Void
    @State private var working = false
    /// A plan waiting for the person's yes.
    @State private var asking: MemoryStop.Pending?
    /// What the last press said, on this row.
    @State private var said: String?
    /// Where Monitor opens on this program, when the row cannot finish the job itself.
    @State private var monitorLink: String?

    var body: some View {
        let offer = PanelStop.offer(for: row.group)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                // the name side opens Monitor: the place to see what a group is made of
                MenuRowButton(action: { SettingsOpener.open(target: "monitor") }) {
                    HStack(alignment: .center, spacing: 8) {
                        icon.frame(width: 20, height: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).font(.callout.weight(.medium))
                            if let detail = row.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                            if case .locked(let reason) = offer {
                                Text(reason).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(row.sizeText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                switch offer {
                case .quit:
                    Button("Quit") { begin() }
                        .disabled(working || asking != nil)
                        .help("Quit \(row.name) and its helpers, like ⌘Q — save prompts still appear")
                case .stop:
                    Button("Stop") { begin() }
                        .disabled(working || asking != nil)
                        .help("Ask \(row.name) to stop; nothing is forced")
                case .locked:
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Not offered here")
                }
            }
            if let asking {
                confirmation(asking)
            }
            if let said {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(said).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let monitorLink {
                        Button("Open in \(Names.Screen.monitor)") { SettingsOpener.open(target: monitorLink) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// The plan's own words and action; Cancel sends nothing.
    private func confirmation(_ plan: MemoryStop.Pending) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.title).font(.callout.weight(.semibold))
                Text(plan.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { asking = nil }
                        .keyboardShortcut(.cancelAction)
                    Button(plan.actionTitle) { confirm(plan) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    /// Plans from the live process table now.
    private func begin() {
        said = nil
        monitorLink = nil
        switch PanelStop.begin(group: row.group) {
        case .ask(let plan): asking = plan
        case .say(let why): said = why
        case .openMonitor(let reason, let link):
            said = reason
            monitorLink = link
        }
    }

    private func confirm(_ plan: MemoryStop.Pending) {
        asking = nil
        working = true
        Task { @MainActor in
            let done = await PanelStop.confirm(plan, group: row.group.name)
            said = done.message
            monitorLink = done.monitorLink
            reload()
            working = false
        }
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
