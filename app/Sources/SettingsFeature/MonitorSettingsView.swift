import SwiftUI
import AnalyzersKit
import UIComponents

/// Monitor pane: the bigger sibling of the menu's Monitor tab — more rows,
/// search, the same live pressure signal and Stop/Quit actions.
struct MonitorSettingsView: View {

    @State private var groups: [ProcessGroup] = []
    @State private var pressure: LiveStats.Pressure = .normal
    /// Same instance the delegate keeps alive — one watcher, many surfaces.
    private var thermal: ThermalWatcher { ThermalWatcher.shared }
    @State private var search = ""
    @AppStorage("monitorRefreshSeconds") private var refresh = 5

    /// A group matches if the parent OR any helper matches; a parent match
    /// keeps the whole family, a helper match trims to matching helpers.
    private var filtered: [ProcessGroup] {
        guard !search.isEmpty else { return groups }
        let needle = search.lowercased()
        func matches(_ proc: LiveProcess) -> Bool {
            proc.friendlyName.lowercased().contains(needle)
                || proc.rawName.lowercased().contains(needle)
        }
        return groups.compactMap { group in
            if matches(group.parent) { return group }
            let kids = group.children.filter(matches)
            return kids.isEmpty ? nil : ProcessGroup(parent: group.parent, children: kids)
        }
    }

    var body: some View {
        PaneScaffold(symbol: "gauge.with.dots.needle.67percent", color: .orange, title: "Monitor",
                     caption: "Every process holding real memory right now — resident RAM, the number the guard acts on.") {
            Section {
                HStack {
                    Circle()
                        .fill(pressure == .normal ? .green
                              : pressure == .warning ? .orange : .red)
                        .frame(width: 8, height: 8)
                    Text("Memory pressure: \(pressure.label)")
                        .foregroundStyle(pressure == .normal ? .secondary : .primary)
                    if thermal.isElevated {
                        BadgeCapsule(text: "THROTTLING", color: .red)
                            .help("macOS is slowing the CPU to cool down — receipts in reports/thermal.log")
                    } else if thermal.state == .fair {
                        BadgeCapsule(text: "WARM", color: .orange)
                    }
                    Spacer()
                    Picker("", selection: $refresh) {
                        Text("2s").tag(2)
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("Off").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }
                TextField("Filter by name…", text: $search)
                    .textFieldStyle(.roundedBorder)
            }

            if !filtered.isEmpty {
                Section("Processes") {
                    ForEach(filtered) { group in
                        if group.children.isEmpty {
                            ProcessRow(proc: group.parent) { load() }
                        } else {
                            DisclosureGroup {
                                ProcessRow(proc: group.parent) { load() }
                                ForEach(group.children) { child in
                                    ProcessRow(proc: child) { load() }
                                }
                            } label: {
                                groupLabel(group)
                            }
                        }
                    }
                }
            }
            if filtered.isEmpty {
                Section {
                    Text(search.isEmpty
                         ? "No process is holding more than 128 MB right now."
                         : "No process matches “\(search)”.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: load)
        .task(id: refresh) {
            guard refresh > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(refresh)))
                load()
            }
        }
    }

    /// Family header: real app icon when the parent is a GUI app, rolled-up
    /// total on the right — the row Activity Monitor never gives you.
    private func groupLabel(_ group: ProcessGroup) -> some View {
        HStack(spacing: 8) {
            if let app = NSRunningApplication(processIdentifier: pid_t(group.parent.pid)),
               let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                IconTile(symbol: "square.stack.3d.up.fill", color: .orange, side: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(group.parent.friendlyName)
                    .font(.callout.weight(.medium))
                Text("\(group.children.count) helper\(group.children.count == 1 ? "" : "s") · pid \(group.parent.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(group.totalText)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func load() {
        groups = LiveStats.groupedSnapshot(limit: 30, minimumMB: 128)
        pressure = LiveStats.memoryPressure()
    }
}
