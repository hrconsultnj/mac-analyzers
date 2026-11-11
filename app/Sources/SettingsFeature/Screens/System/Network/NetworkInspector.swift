import AnalyzersKit
import SwiftUI

/// The selected process in a snapshot, in full.
struct NetworkInspector: View {
    let row: NetworkProcessRow
    let onShowInFinder: () -> Void

    var body: some View {
        Form {
            Section {
                Text(row.name).font(.headline)
                LabeledContent("Kind", value: row.kindTitle)
                LabeledContent("Running", value: row.runningTitle)
                LabeledContent("Process ID", value: String(row.pid))
            }
            Section("Traffic Since It Started") {
                LabeledContent("Downloaded", value: ByteSize.format(row.downloaded))
                LabeledContent("Uploaded", value: ByteSize.format(row.uploaded))
                LabeledContent("Total", value: ByteSize.format(row.total))
                LabeledContent("Share of All Traffic") {
                    Text(row.share, format: .percent.precision(.fractionLength(0)))
                }
            }
            if let path = row.path {
                Section("Where It Lives") {
                    Text(path).font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            Section {
                Button("Show in Finder", action: onShowInFinder).disabled(row.path == nil)
            } footer: {
                Text("Counts are totals since the program started, not a live speed. Nothing here blocks or changes network traffic.")
            }
        }
        .formStyle(.grouped)
    }
}

/// A selected app: its programs and what they moved together.
struct NetworkGroupInspector: View {
    let group: NetworkGroup

    var body: some View {
        Form {
            Section {
                Text(group.name).font(.headline)
                LabeledContent("Programs", value: group.countText)
                LabeledContent("Running", value: "\(group.runningCount) of \(group.count)")
            }
            Section("Traffic Since It Started") {
                LabeledContent("Downloaded", value: ByteSize.format(group.downloaded))
                LabeledContent("Uploaded", value: ByteSize.format(group.uploaded))
                LabeledContent("Total", value: ByteSize.format(group.total))
                LabeledContent("Share of All Traffic") {
                    Text(group.share, format: .percent.precision(.fractionLength(0)))
                }
            }
            Section("Programs") {
                ForEach(group.rows) { row in
                    LabeledContent(row.name, value: ByteSize.format(row.total))
                }
            }
        }
        .formStyle(.grouped)
    }
}
