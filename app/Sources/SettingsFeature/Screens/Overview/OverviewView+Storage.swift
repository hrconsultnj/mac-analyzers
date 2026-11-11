import SwiftUI
import AnalyzersKit
import UIComponents

/// Storage: free space, what the latest preview says can be reclaimed, and what
/// cleanups freed this week. The runway row appears only when the disk is
/// filling faster than a month.
extension OverviewView {

    func storageBox(_ model: OverviewModel) -> some View {
        OverviewBox(title: Names.Group.storage, symbol: "internaldrive") {
            if let disk = store.disk {
                OverviewValueRow(label: "Free Space", value: "\(disk.freeText) of \(disk.totalText)",
                                 action: { navigator.open(target: "disk") })
                ProgressView(value: disk.usedFraction)
                    .tint(disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.75 ? .orange : .accentColor)
                    .accessibilityLabel("Disk used")
            }
            if let runway, runway.urgent {
                OverviewValueRow(label: "Full In", value: runway.text, action: { navigator.open(target: "disk") })
            }
            if let week {
                // only while the newest cleanup run was a preview; after an apply there is nothing to show
                if let reclaimable = week.latestReclaimableBytes {
                    OverviewValueRow(label: "Can Be Reclaimed", value: ByteSize.format(reclaimable),
                                     action: { navigator.open(target: "caches") },
                                     caption: "From the latest preview. Nothing is deleted until you review it.")
                }
                OverviewValueRow(label: "Removed This Week", value: ByteSize.format(week.storageFreedBytes),
                                 action: { navigator.open(target: "trends:storage") })
            }
        }
    }
}
