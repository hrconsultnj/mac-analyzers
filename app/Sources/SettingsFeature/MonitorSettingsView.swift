import SwiftUI
import AnalyzersKit
import UIComponents

/// Monitor pane: the bigger sibling of the menu's Monitor tab — more rows,
/// search, the same live pressure signal and Stop/Quit actions.
struct MonitorSettingsView: View {

    @State private var processes: [LiveProcess] = []
    @State private var pressure: LiveStats.Pressure = .normal
    @State private var search = ""
    @AppStorage("monitorRefreshSeconds") private var refresh = 5

    private var filtered: [LiveProcess] {
        guard !search.isEmpty else { return processes }
        let needle = search.lowercased()
        return processes.filter {
            $0.friendlyName.lowercased().contains(needle)
                || $0.rawName.lowercased().contains(needle)
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

            let devs = filtered.filter(\.isDev)
            let apps = filtered.filter { !$0.isDev }

            if !devs.isEmpty {
                Section("Dev Processes") {
                    ForEach(devs) { proc in ProcessRow(proc: proc) { load() } }
                }
            }
            if !apps.isEmpty {
                Section("Apps & Helpers") {
                    ForEach(apps) { proc in ProcessRow(proc: proc) { load() } }
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

    private func load() {
        processes = LiveStats.snapshot(limit: 40, minimumMB: 128)
        pressure = LiveStats.memoryPressure()
    }
}
