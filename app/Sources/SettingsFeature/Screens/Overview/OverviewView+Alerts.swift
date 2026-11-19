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
    /// instead; a batch that is still going is never queued twice. Login & Startup Items is included only when System
    /// Events permission has already been granted, so the batch never stalls behind an unexpected permission modal.
    func scanEverything() {
        guard !jobs.batchIsActive else { return }
        if LiveStats.memoryPressure() == .critical {
            scanNotice = "Memory is critically low, so the scans were not started. Close something, then try again."
            return
        }
        scanNotice = nil
        let includeLoginItems = SystemEventsPermission.current() == .granted
        loginItemsLeftOut = !includeLoginItems
        jobs.enqueueBatch(ScanPlan.requests(storage: config.storage, includeLoginItems: includeLoginItems), trigger: .user)
    }

    @ViewBuilder var scanMessage: some View {
        if let scanNotice {
            OverviewBox(title: Names.Overview.scanEverything, symbol: "exclamationmark.triangle") {
                HStack {
                    Label(scanNotice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                    Spacer(minLength: 8)
                    Button(Names.WhatsNew.dismiss) { self.scanNotice = nil }
                }
            }
            .onChange(of: jobs.hasWork) {
                if jobs.hasWork { self.scanNotice = nil }
            }
        }
    }

    @ViewBuilder var running: some View {
        if !jobs.batchIsActive, !jobs.batch.isEmpty {
            OverviewBox(title: Names.Overview.scanEverything, symbol: "checkmark.circle") {
                Text(batchProgress(jobs.batch))
                    .foregroundStyle(.secondary)
                if loginItemsLeftOut {
                    Text(Self.loginItemsLeftOutNote)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(Names.WhatsNew.dismiss) {
                    jobs.dismissFinishedBatch()
                    loginItemsLeftOut = false
                }
            }
        }
        let active = [jobs.running].compactMap { $0 } + jobs.queued
        if !active.isEmpty {
            let batchIDs = jobs.batchIsActive ? Set(jobs.batch.map(\.id)) : []
            let waitingBatch = jobs.queued.filter { batchIDs.contains($0.id) }
            let visibleJobs = [jobs.running].compactMap { $0 } + (jobs.batchIsActive
                ? jobs.queued.filter { !batchIDs.contains($0.id) }
                : jobs.queued)
            OverviewBox(title: "Running Now", symbol: "play.circle") {
                if jobs.batchIsActive {
                    HStack {
                        Text(batchProgress(jobs.batch))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if !waitingBatch.isEmpty {
                            Button(Names.Overview.cancelTheRest) { jobs.cancelRestOfBatch() }
                        }
                    }
                }
                ForEach(visibleJobs) { job in
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
                if !waitingBatch.isEmpty {
                    Text(waitingBatch.count == 1
                         ? "1 more scan waiting in this batch"
                         : "\(waitingBatch.count) more scans waiting in this batch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if jobs.batchIsActive, loginItemsLeftOut {
                    Text(Self.loginItemsLeftOutNote)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Finished scans are only the ones that succeeded. Failed and cancelled scans are named beside that count,
    /// so Cancel the Rest never reads as "12 of 13 scans done" while the first one is still running.
    private func batchProgress(_ batch: [Job]) -> String {
        let succeeded = batch.filter { if case .succeeded = $0.state { true } else { false } }.count
        let failed = batch.filter { if case .failed = $0.state { true } else { false } }.count
        let cancelled = batch.filter(\.state.isCancelled).count
        var parts = ["\(succeeded) of \(batch.count) scans finished"]
        if failed == 1 { parts.append("1 failed") }
        else if failed > 1 { parts.append("\(failed) failed") }
        if cancelled == 1 { parts.append("1 not started") }
        else if cancelled > 1 { parts.append("\(cancelled) not started") }
        return parts.joined(separator: " · ")
    }

    private static let loginItemsLeftOutNote =
        "Login & Startup Items was left out, because macOS has not allowed System Events yet. Run Audit on that screen."

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
