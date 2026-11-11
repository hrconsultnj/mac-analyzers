import AnalyzersKit
import NotifierKit
import SwiftUI
import UIComponents

/// Tells the user when a job ends while they are not looking at the main
/// window. Attached to the menu-bar label, the one view alive for the app's
/// whole life; a click on the notification opens `job:<uuid>` in Activity.
/// A job you stopped yourself is not announced.
private struct JobFinishNotifier: ViewModifier {
    let store: JobStore

    /// Moves when any job finishes, whichever order they finish in.
    private var lastFinish: Date? { store.jobs.compactMap(\.finishedAt).max() }

    func body(content: Content) -> some View {
        content.onChange(of: lastFinish) { _, finishedAt in
            guard let finishedAt,
                  let job = store.jobs.last(where: { $0.finishedAt == finishedAt }) else { return }
            switch job.state {
            case .succeeded, .failed:
                let snapshot = job.activitySnapshot
                NotificationPoster.shared.postJobFinished(
                    id: job.id, task: job.kind.title, result: snapshot.summary.text,
                    failed: snapshot.status == .failed)
            default:
                break
            }
        }
    }
}

public extension View {
    /// Posts a notification when a tracked job ends and the main window is not
    /// the key window.
    func notifyWhenJobsFinish(_ store: JobStore) -> some View {
        modifier(JobFinishNotifier(store: store))
    }
}
