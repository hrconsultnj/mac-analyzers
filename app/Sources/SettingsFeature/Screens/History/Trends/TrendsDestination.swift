import SwiftUI
import AnalyzersKit
import UIComponents

@ViewBuilder
func trendsDestination(_ route: TrendsRoute) -> some View {
    switch route {
    case .kills(let period):
        GuardEventListDetailView(title: "Runaways Stopped", symbol: "xmark.octagon.fill", color: .red,
                                 caption: "Every kill in the \(period.label.lowercased()) window — newest first.",
                                 period: period, category: .killed)
    case .spikes(let period):
        GuardEventListDetailView(title: "Spikes Caught", symbol: "arrow.up.right", color: .orange,
                                 caption: "Every memory spike flagged in the \(period.label.lowercased()) window.",
                                 period: period, category: .spikes)
    case .pressure(let period):
        GuardEventListDetailView(title: "Pressure Alerts", symbol: "exclamationmark.triangle.fill", color: .orange,
                                 caption: "Cap-exceeded and system pressure events in the \(period.label.lowercased()) window.",
                                 period: period, category: .pressure)
    case .cpuHogs(let period):
        GuardEventListDetailView(title: "CPU Hogs Flagged", symbol: "cpu", color: .purple,
                                 caption: "Processes that sustained high CPU in the \(period.label.lowercased()) window.",
                                 period: period, category: .cpu)
    case .memoryFreed(let period):
        MemoryFreedDetailView(period: period)
    case .diskReclaimed(let period):
        DiskReclaimedDetailView(period: period)
    case .reclaimableNow(let period):
        ReclaimableNowDetailView(period: period)
    case .offender(let name, let period):
        OffenderDetailView(name: name, period: period)
    }
}
