import AnalyzersKit
import Foundation

/// How a screen finds "its" job again. The store lives as long as the app and
/// a screen lives as long as its window, so a screen that started a preview
/// adopts the store's job of its kind when it appears: the same progress, or
/// the same result, after the window was closed and opened again.
extension JobStore {

    /// The job a screen should show: one still queued or running if there is
    /// one, otherwise the most recent that matches.
    func latest(where matches: (Job) -> Bool) -> Job? {
        let found = jobs.filter(matches)
        return found.last { !$0.state.isFinished } ?? found.last
    }

    func latest(_ kind: JobKind, intents: Set<JobIntent>) -> Job? {
        latest { $0.kind == kind && intents.contains($0.intent) }
    }

    /// What a screen may take back when it appears: a job still queued or
    /// running, always; a finished one only while it is recent and nobody
    /// dismissed it. Discard, New preview and Try again dismiss.
    func adoptable(where matches: (Job) -> Bool, maxAge: TimeInterval = JobStore.reviewWindow,
                   now: Date = Date()) -> Job? {
        latest { job in
            guard matches(job) else { return false }
            if job.isActive { return true }
            guard !dismissed.contains(job.id), let end = job.finishedAt else { return false }
            return now.timeIntervalSince(end) <= maxAge
        }
    }

    func adoptable(kind: JobKind, intents: Set<JobIntent>, maxAge: TimeInterval = JobStore.reviewWindow,
                   now: Date = Date()) -> Job? {
        adoptable(where: { $0.kind == kind && intents.contains($0.intent) }, maxAge: maxAge, now: now)
    }
}

/// A job's place in its life, comparable so `onChange` can see a job move on.
struct JobStamp: Equatable {
    enum Stage: Int { case queued, running, succeeded, failed, cancelled }

    let id: UUID?
    let stage: Stage?

    @MainActor init(_ job: Job?) {
        id = job?.id
        stage = job.map { job in
            switch job.state {
            case .queued: .queued
            case .running: .running
            case .succeeded: .succeeded
            case .failed: .failed
            case .cancelled: .cancelled
            }
        }
    }

    var isFinished: Bool { stage.map { $0.rawValue >= Stage.succeeded.rawValue } ?? false }
}

extension Job {
    var stamp: JobStamp { JobStamp(self) }

    /// When a finished preview stops being something to apply; nil while it runs.
    var reviewExpiry: Date? { finishedAt.map { $0.addingTimeInterval(JobStore.reviewWindow) } }

    /// Still queued or running.
    var isActive: Bool { !state.isFinished }

    /// Why it failed, in words, or nil.
    var failureMessage: String? {
        if case .failed(let failure) = state { failure.message } else { nil }
    }

    /// Returns once the job has finished. Polls rather than observing: an
    /// observation callback fires before the new value is stored, and acting
    /// on it can read the old state.
    func waitUntilFinished() async {
        while !state.isFinished {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
