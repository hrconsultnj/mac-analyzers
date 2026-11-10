import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory lens: every process that runs on its own, as a sortable table.
extension MonitorSettingsView {

    /// Name / Memory / PID, sortable — the standalone (non-family) rows only.
    /// Both actions the old row offered stay VISIBLE in a trailing column:
    /// right-click is a power-user gesture, and burying the one thing this
    /// screen exists to let you do behind it would hide it from exactly the
    /// people this pass is for. The context menu is the shortcut, not the
    /// only door.
    @ViewBuilder var standaloneSection: some View {
        if !standaloneProcs.isEmpty {
            Section("Single processes — \(standaloneProcs.count) · \(MemorySize.text(standaloneProcs.reduce(0) { $0 + $1.memoryBytes }))") {
                Table(standaloneProcs, selection: $selectedPID, sortOrder: $sortOrder) {
                    TableColumn("Name", sortUsing: KeyPathComparator<LiveProcess>(\.friendlyName)) { proc in
                        Text(proc.friendlyName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(proc.friendlyName)
                    }
                    .width(min: 140, ideal: 190)
                    // what a macOS service is for where that is known,
                    // otherwise the command that started the process
                    TableColumn("What it is") { proc in
                        let role = ProcessGlossary.systemRole(of: proc.friendlyName)
                        let detail = role
                            ?? (proc.rawName == proc.friendlyName ? "" : proc.rawName)
                        Text(detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            // a sentence reads from its start; a path is told
                            // apart by its end
                            .truncationMode(role == nil ? .middle : .tail)
                            .help(detail)
                    }
                    .width(min: 150, ideal: 260)
                    TableColumn("Memory", sortUsing: KeyPathComparator<LiveProcess>(\.memoryBytes)) { proc in
                        Text(proc.memoryText)
                            .monospacedDigit()
                            .foregroundStyle(proc.memoryMB > 4096 ? .orange : .secondary)
                    }
                    .width(min: 64, ideal: 72, max: 90)
                    TableColumn("PID", sortUsing: KeyPathComparator<LiveProcess>(\.pid)) { proc in
                        // String, not an interpolated number — a pid is an
                        // identifier and must not gain a thousands separator
                        Text(String(proc.pid))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 44, ideal: 56, max: 70)
                    TableColumn("") { proc in
                        HStack(spacing: Tokens.Space.s) {
                            // never offered for macOS's own processes
                            if proc.canQuit {
                                Button(proc.isDev ? "Stop" : "Quit") { stop(proc) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(proc.isDev
                                        ? "Stop \(proc.friendlyName)"
                                        : "Quit \(proc.friendlyName)")
                            }
                            Button {
                                navigator.push(.memory(.dossier(
                                    DossierRoute(name: proc.friendlyName, pid: proc.pid))))
                            } label: { Image(systemName: "info.circle") }
                                .buttonStyle(.borderless)
                                .help("What this process is doing")
                                .accessibilityLabel("Details for \(proc.friendlyName)")
                        }
                    }
                    .width(76)
                }
                // grows with the list up to a point, then scrolls — hundreds
                // of rows stay cheap because the table only draws what shows
                .frame(height: min(max(220, CGFloat(standaloneProcs.count) * 28 + 36), 460))
                .contextMenu(forSelectionType: Int.self) { selection in
                    if let pid = selection.first,
                       let proc = standaloneProcs.first(where: { $0.pid == pid }) {
                        Button("Dossier…") {
                            navigator.push(.memory(.dossier(
                                DossierRoute(name: proc.friendlyName, pid: proc.pid))))
                        }
                        if proc.canQuit {
                            Button(proc.isDev ? "Stop" : "Quit") { stop(proc) }
                        }
                    }
                }
            }
        }
    }
}
