import SwiftUI
import AnalyzersKit
import UIComponents

/// The top of the panel while a job runs or waits: its name, the last line it
/// printed, and Stop. Absent otherwise, so a quiet app's panel is unchanged.
/// Clicking it opens the job in Activity.
struct MenuJobsStrip: View {
    @Environment(JobStore.self) private var store

    var body: some View {
        if let job = store.running ?? store.queued.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        SettingsOpener.open(target: "job:\(job.id.uuidString)")
                    } label: {
                        HStack(spacing: 8) {
                            if job.state.isQueuedOnly {
                                Image(systemName: "clock").foregroundStyle(.secondary)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(job.kind.title).font(.callout.weight(.medium))
                                    if let started = job.startedAt {
                                        Text(started, style: .timer)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    if waiting > 0 {
                                        Text("+\(waiting) waiting").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text(lastLine(job))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open in Activity")
                    Button("Stop") { job.cancel() }
                        .controlSize(.small)
                        .help("Stop this job and everything it started. Quitting Mac Analyzers asks whether to stop it or let it finish.")
                }
            }
            .padding(8)
            .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.tile))
            .accessibilityElement(children: .contain)
        }
    }

    private var waiting: Int { store.running == nil ? max(0, store.queued.count - 1) : store.queued.count }

    /// The last thing the script said, or what it is about to do.
    private func lastLine(_ job: Job) -> String {
        if job.state.isQueuedOnly { return "Waiting for the running job to finish" }
        let line = job.lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line?.trimmingCharacters(in: .whitespaces) ?? job.step ?? "Starting…"
    }
}

private extension Job.State {
    var isQueuedOnly: Bool { if case .queued = self { true } else { false } }
}
