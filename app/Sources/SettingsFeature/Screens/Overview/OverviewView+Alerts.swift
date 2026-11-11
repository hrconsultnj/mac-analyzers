import SwiftUI
import AnalyzersKit
import UIComponents

/// Needs Attention (only when true) and Running Now, across the full width.
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

    @ViewBuilder var running: some View {
        let active = [jobs.running].compactMap { $0 } + jobs.queued
        if !active.isEmpty {
            OverviewBox(title: "Running Now", symbol: "play.circle") {
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
