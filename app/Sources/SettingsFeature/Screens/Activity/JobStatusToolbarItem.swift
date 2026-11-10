import SwiftUI
import AnalyzersKit
import UIComponents

/// The shell's status item, present on every screen: while a job runs a
/// spinner, "<task>… 0:42" and a stop button; for 30 seconds after one ends
/// its outcome; nothing otherwise. Clicking it opens that job in Activity.
///
/// Attach it to the split view (`MainWindowView` does): a toolbar attached to
/// a `NavigationStack` itself is silently dropped.
struct JobStatusToolbarItem: ToolbarContent {
    let store: JobStore
    let navigator: Navigator

    var body: some ToolbarContent {
        ToolbarItem(placement: .status) {
            JobStatusItemView(store: store, navigator: navigator)
        }
    }
}

private struct JobStatusItemView: View {
    let store: JobStore
    let navigator: Navigator

    /// How long a finished job's outcome stays up.
    private static let linger: TimeInterval = 30

    private var recentlyFinished: Job? {
        store.jobs
            .filter { job in
                guard let end = job.finishedAt else { return false }
                if case .cancelled = job.state { return false }     // you stopped it; you know
                return Date().timeIntervalSince(end) < Self.linger
            }
            .max { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
    }

    var body: some View {
        if let job = store.running {
            running(job)
        } else if let job = recentlyFinished, let end = job.finishedAt {
            // redrawn once, when the 30 seconds are up
            TimelineView(.explicit([end.addingTimeInterval(Self.linger)])) { context in
                if context.date < end.addingTimeInterval(Self.linger) { finished(job) }
            }
        }
    }

    private func running(_ job: Job) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Button { open(job) } label: {
                HStack(spacing: Tokens.Space.s) {
                    ProgressView().controlSize(.small)
                    elapsed(job)
                }
            }
            .buttonStyle(.plain)
            .help("Open \(job.kind.title) in Activity")
            Button { job.cancel() } label: {
                Image(systemName: "stop.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Stop \(job.kind.title)")
            .accessibilityLabel("Stop \(job.kind.title)")
        }
    }

    /// "Cleaning caches… 0:42" — the group line the script is on, or the
    /// task's name, with a clock the system keeps redrawing.
    @ViewBuilder private func elapsed(_ job: Job) -> some View {
        let label = (job.step ?? job.kind.title) + "… "
        if let started = job.startedAt {
            (Text(label) + Text(started, style: .timer).monospacedDigit())
                .lineLimit(1)
        } else {
            Text(label).lineLimit(1)
        }
    }

    private func finished(_ job: Job) -> some View {
        let snapshot = job.activitySnapshot
        let ok = snapshot.status == .done
        return Button { open(job) } label: {
            Label(ok ? "\(snapshot.summary.text) ✓" : "\(job.kind.title) \(snapshot.status == .failed ? "failed" : "stopped")",
                  systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(ok ? Tokens.Status.safe.tint : Tokens.Status.caution.tint)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("Open \(job.kind.title) in Activity")
    }

    private func open(_ job: Job) {
        navigator.open(target: "job:\(job.id.uuidString)")
    }
}
