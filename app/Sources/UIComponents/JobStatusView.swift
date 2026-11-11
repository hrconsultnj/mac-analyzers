import AnalyzersKit
import SwiftUI

/// One job's state in one line: queued, running (with its current step and a
/// Stop button), or how it ended. Used wherever a job is listed — the owning
/// screen, Activity, the toolbar — so they cannot disagree.
public struct JobStatusView: View {
    let job: Job

    public init(job: Job) { self.job = job }

    public var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: job.kind.symbol)
                .foregroundStyle(job.kind.tint)
                .frame(width: Tokens.Icon.row)
            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                HStack(spacing: Tokens.Space.s) {
                    Text(job.kind.title).font(Tokens.Typography.rowTitleKey)
                    BadgeCapsule(text: job.intent.title.uppercased(), color: job.kind.tint)
                }
                Text(detail)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Tokens.Space.m)
            trailing
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var trailing: some View {
        switch job.state {
        case .queued:
            Button("Cancel") { job.cancel() }
        case .running:
            ProgressView().controlSize(.small)
            Button("Stop") { job.cancel() }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.Status.safe.tint)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.Status.caution.tint)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(Tokens.Status.inert.tint)
        }
    }

    private var detail: String {
        switch job.state {
        case .queued: "Waiting for the running job to finish."
        case .running: job.step ?? "Working…"
        case .succeeded: job.note ?? "Finished."
        case .failed(let failure): failure.message
        case .cancelled(let partial):
            partial ? "Stopped. Items already handled are listed in the receipts." : "Stopped before anything changed."
        }
    }
}
