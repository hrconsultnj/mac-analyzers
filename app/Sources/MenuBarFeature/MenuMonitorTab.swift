import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The Monitor tab: the biggest processes right now.
extension MenuContentView {

    // MARK: - Monitor tab

    /// Mini live monitor: what the guard can see and act on — resident RAM
    /// across ALL big processes (apps, helpers, dev tools), stoppable per row.
    @ViewBuilder var monitorTab: some View {
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
}
