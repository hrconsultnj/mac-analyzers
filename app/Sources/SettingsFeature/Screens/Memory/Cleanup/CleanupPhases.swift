import AnalyzersKit
import SwiftUI
import UIComponents

/// What the screen shows when there is no review to look at: before a preview (what the
/// cleanup is, and its past runs), while a job works, and when it did not finish.

struct CleanupIdle: View {
    let scope: MemoryCleanupModel.Scope
    let preview: () -> Void

    var body: some View {
        List {
            Section {
                Label(scope.title, systemImage: scope.symbol).font(.headline)
                Text(explanation)
                Button(Names.Cleanup.preview, systemImage: "eye", action: preview)
                    .buttonStyle(.glassProminent)
            } footer: {
                Text("A preview only looks. Nothing is closed until you choose Close Programs.")
            }
            RunHistoryList(kinds: [.memoryClean, .reclaim], logs: [.memoryClean, .reclaim], limit: 8,
                           emptyText: "Nothing has been cleaned up yet.")
        }
    }

    private var explanation: String {
        switch scope {
        case .leftovers:
            "Finds developer programs that nothing is using any more: idle dev servers, orphaned tools, emulators and containers. Programs that belong to a live coding session are never touched."
        case .everythingNow:
            "Frees as much memory as it can right now: every developer program that is not part of a live coding session, and, if you choose, the apps on your list. Apps are asked to quit, not forced."
        }
    }
}

struct CleanupRunning: View {
    let job: Job
    let applying: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                ProgressView().controlSize(.small)
                Text(job.step ?? (applying ? "Closing programs…" : "Looking for programs…"))
                    .font(.headline)
            }
            .padding([.horizontal, .top])
            LiveOutputView(job: job)
        }
    }
}

struct CleanupFailed: View {
    let message: String
    let preview: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Didn't Finish", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(Names.Review.previewAgain, action: preview)
        }
    }
}
