import SwiftUI
import AnalyzersKit
import UIComponents

@MainActor @ViewBuilder
func trendsDestination(_ route: TrendsRoute) -> some View {
    switch route {
    case .kills(let period):
        GuardEventListDetailView(title: "Runaways Stopped", period: period, category: .killed)
    case .spikes(let period):
        GuardEventListDetailView(title: "Spikes Caught", period: period, category: .spikes)
    case .pressure(let period):
        GuardEventListDetailView(title: "Pressure Alerts", period: period, category: .pressure)
    case .cpuHogs(let period):
        GuardEventListDetailView(title: "CPU Hogs Flagged", period: period, category: .cpu)
    case .memoryFreed(let period):
        MemoryFreedDetailView(period: period)
    case .diskReclaimed(let period):
        DiskReclaimedDetailView(period: period)
    case .removedProject(let project, let period):
        DiskReclaimedDetailView(period: period, project: project)
    case .reclaimableNow:
        ReclaimableNowDetailView()
    case .offender(let name, let period):
        OffenderDetailView(name: name, period: period)
    }
}
