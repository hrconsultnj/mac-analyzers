import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// REVIEW › Undo — the ledger of reversibility. A kill-guard people trust
/// is one that can un-kill: janitor items come back from the Trash with a
/// click (receipt written), and guard-killed dev servers offer their
/// logged command for relaunch.
struct UndoView: View {

    @State private var trashed: [TrashedItem] = []
    @State private var kills: [GuardEvent] = []
    @State private var restoreError: String?
    @State private var copiedID: String?

    var body: some View {
        PaneScaffold(symbol: "arrow.uturn.backward", color: .gray, title: "Undo",
                     caption: "What can be brought back — janitor items restored from the Trash with a receipt, and the commands behind stopped dev servers.") {
            Section("Moved to Trash by the Janitor") {
                if let restoreError {
                    Label(restoreError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                if trashed.isEmpty {
                    Text("Nothing to restore — the Janitor hasn't moved anything to the Trash recently.")
                        .foregroundStyle(.secondary)
                }
                ForEach(trashed) { item in
                    HStack(spacing: 8) {
                        DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.originalPath),
                                 title: item.basename,
                                 subtitle: item.originalPath,
                                 trailing: item.sizeText)
                        switch item.restorability {
                        case .restorable:
                            Button("Restore") { restore(item) }
                        case .trashCopyGone:
                            Text("Trash emptied")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .pathOccupied:
                            Text("Path occupied")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Something new exists at the original path — restore manually from the Trash if needed.")
                        case .destinationUnknown:
                            Text("Restore manually")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("This item was trashed before the app tracked exactly where files came from, so restoring would mean guessing which file in the Trash is the right one — the app won't guess. Drag it back yourself if you need it.")
                        }
                    }
                }
            }

            Section("Stopped dev servers (recent)") {
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
                                 badge: ("KILLED", .red))
                        Button(copiedID == event.id ? "Copied" : "Copy command") {
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
