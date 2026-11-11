import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// REVIEW › Undo — the ledger of reversibility. A kill-guard people trust
/// is one that can un-kill: janitor and temp-clean items come back from the
/// Trash with a click (receipt written), and guard-killed dev servers offer their
/// logged command for relaunch.
struct UndoView: View {

    @State private var trashed: [TrashedItem] = []
    @State private var kills: [GuardEvent] = []
    @State private var restoreError: String?
    @State private var copiedID: String?

    var body: some View {
        PaneScaffold(symbol: "arrow.uturn.backward", color: .gray, title: Names.Screen.undo,
                     caption: "What can be brought back — items the Janitor or Temp & Agents moved to the Trash, restored with a receipt, and the commands behind stopped dev servers.") {
            Section("Moved to the Trash") {
                if let restoreError {
                    Label(restoreError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                if trashed.isEmpty {
                    Text("Nothing to restore — nothing has been moved to the Trash by a cleaner recently.")
                        .foregroundStyle(.secondary)
                }
                ForEach(trashed) { item in
                    HStack(spacing: 8) {
                        DataCard(appIcon: NSWorkspace.shared.icon(
                                    forFile: item.isGroup ? (item.trashPath ?? item.originalPath)
                                                          : item.originalPath),
                                 title: item.basename,
                                 subtitle: item.originalPath,
                                 trailing: item.sizeText,
                                 badge: (item.source.uppercased(),
                                         item.source == "Janitor" ? .orange : .mint))
                        switch item.restorability {
                        case .restorable:
                            Button("Restore") { restore(item) }
                        case .trashCopyGone:
                            Text("Trash Emptied")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .pathOccupied:
                            Text("Path Occupied")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Something new is at the original path — restore from the Trash")
                        case .destinationUnknown:
                            Text("Restore Manually")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Trashed before the app tracked origins — drag it back from the Trash yourself")
                        }
                    }
                }
            }

            Section("Stopped Dev Servers (Recent)") {
                if kills.isEmpty {
                    Text("The guard hasn't stopped anything recently.")
                        .foregroundStyle(.secondary)
                }
                ForEach(kills.prefix(15)) { event in
                    HStack(spacing: 8) {
                        DataCard(symbol: "xmark.octagon.fill", color: .red,
                                 title: event.friendlyName,
                                 subtitle: "\(event.processName) · \(event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))",
                                 trailing: event.residentText,
                                 badge: ("Killed", .red))
                        Button(copiedID == event.id ? "Copied" : "Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(event.processName, forType: .string)
                            copiedID = event.id
                        }
                        .help(event.processName.count >= 140
                              ? "This command was recorded before the app captured full command lines, so part of it may be missing — check it before running."
                              : "The command as the guard recorded it. You still supply the working directory and environment.")
                    }
                }
            }
        }
        .task { await load() }
    }

    private func restore(_ item: TrashedItem) {
        do {
            try UndoLedger.restore(item)
            restoreError = nil
        } catch {
            restoreError = "Could not restore \(item.basename): \(error.localizedDescription)"
        }
        Task { await load() }
    }

    private func load() async {
        await awaitLoad({
            (UndoLedger.trashedItems(),
             GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog).filter(\.isKill))
        }) {
            trashed = $0.0
            kills = $0.1
        }
    }
}
