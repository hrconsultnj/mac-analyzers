import SwiftUI
import AnalyzersKit
import UIComponents

/// Needs Attention (only when true), Running Now and the Scan Everything batch, across the full width.
/// A row that only navigates is a whole-row button with a chevron; resuming the
/// guard acts in place.
extension OverviewView {

    @ViewBuilder func alerts(_ model: OverviewModel) -> some View {
        if !model.attention.isEmpty {
            OverviewBox(title: "Needs Attention", symbol: "exclamationmark.circle") {
                ForEach(model.attention) { item in
                    switch item.action {
                    case .open(let target):
                        OverviewRow(action: { navigator.open(target: target) }) { label(item) }
                    case .resumeGuard:
                        HStack {
                            label(item)
                            Spacer(minLength: 8)
                            Button("Resume") {
                                do {
                                    try store.setGuardPaused(false)
                                    resumeError = nil
                                    store.reload()
                                } catch {
                                    resumeError = error.localizedDescription
                                }
                            }
                        }
                    }
                }
                if let resumeError {
                    Label(resumeError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    /// Queues every report and preview. Memory this low is no time to start the heaviest scans, so it says so
    /// instead; a batch that is still going is never queued twice.
    func scanEverything() {
        guard !jobs.batchIsActive else { return }
        if LiveStats.memoryPressure() == .critical {
            scanNotice = "Memory is critically low, so the scans were not started. Close something, then try again."
            return
        }
        scanNotice = nil
        jobs.enqueueBatch(ScanPlan.requests(storage: config.storage), trigger: .user)
    }

    @ViewBuilder var scanMessage: some View {
        if let scanNotice {
            Label(scanNotice, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder var running: some View {
        let active = [jobs.running].compactMap { $0 } + jobs.queued
        if !active.isEmpty {
            OverviewBox(title: "Running Now", symbol: "play.circle") {
                if jobs.batchIsActive {
                    HStack {
                        Text("\(jobs.batch.filter { $0.state.isFinished }.count) of \(jobs.batch.count) scans done")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if jobs.queued.contains(where: { queued in jobs.batch.contains { $0.id == queued.id } }) {
                            Button(Names.Overview.cancelTheRest) { jobs.cancelRestOfBatch() }
                        }
                    }
                }
                ForEach(active) { job in
                    HStack {
                        OverviewRow(action: { navigator.open(target: "job:\(job.id.uuidString)") }) {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Names.job(job.kind))
                                    Text(jobs.queued.contains { $0.id == job.id } ? "Waiting for the running job to finish"
                                         : job.step ?? "Working…")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                ProgressView().controlSize(.small)
                            }
                        }
                        Button("Stop") { job.cancel() }
                    }
                }
            }
        }
    }

    private func label(_ item: OverviewModel.Attention) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: item.symbol).foregroundStyle(color(item.tone))
        }
    }

    func color(_ tone: OverviewModel.Tone) -> Color {
        switch tone {
        case .good: .green
        case .caution: .orange
        case .bad: .red
        case .neutral: .secondary
        }
    }
}
