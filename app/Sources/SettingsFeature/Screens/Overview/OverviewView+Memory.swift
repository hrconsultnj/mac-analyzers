import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory: pressure, how much is in use, and the three apps using the most — the
/// first rows of Monitor, from the same census. Every row opens Monitor; an app or tool
/// opens it with that row selected (`monitor:select:<name>`).
extension OverviewView {

    var memoryBox: some View {
        OverviewBox(title: Names.Group.memory, symbol: "memorychip") {
            OverviewValueRow(label: "Memory Pressure", value: store.pressure.label.components(separatedBy: " —")[0],
                             action: { navigator.open(target: "monitor") })
            if let used = panel?.memoryUsedBytes, let total = panel?.memoryTotalBytes {
                OverviewValueRow(label: "In Use", value: "\(MemorySize.text(used)) of \(MemorySize.text(total))",
                                 action: { navigator.open(target: "monitor") })
                ProgressView(value: Double(used), total: Double(max(total, 1)))
                    .accessibilityLabel("Memory in use")
            }
            Divider()
            if let panel {
                ForEach(panel.processes) { row in
                    OverviewValueRow(label: row.name, value: row.sizeText,
                                     // the row's own app or tool, selected in Monitor
                                     action: { navigator.open(target: MemoryStop.monitorLink(forGroup: row.group.name)) })
                }
            } else {
                ProgressView("Reading every process…").controlSize(.small)
            }
        }
    }
}
