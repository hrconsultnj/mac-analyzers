import AnalyzersKit
import Foundation
import Observation

/// What one Storage review screen is showing: the preview it started or took back from the
/// store, that preview's whole run read from its log, the rows made of it, and the review
/// session (ticks) built for that exact preview. Caches & Builds, Downloads and Temp & Agents
/// each own one; the screen around it is `StorageReviewScreen`.
///
/// The rows are read whole by the preview's own banner (`WholeRun`): a Downloads preview of
/// 6,000 files is one run of 600 KB, far more than the log window listings use. If the run
/// cannot be found, or is too large, the screen says so and offers nothing to apply: the
/// kernel refuses it too.
@MainActor @Observable
final class StorageReviewModel {

    /// What the screen is waiting for or showing.
    enum Phase: Equatable {
        case empty
        case running
        case failed(String)
        case stopped
        case loading
        /// The preview's results could not be read (not found, or too large).
        case unreadable(String)
        case ready
        /// Only the last preview in the log is known: shown, never applied.
        case lastKnown
    }

    private(set) var job: Job?
    private(set) var block: WholeRun.Block?
    private(set) var rows: StorageRows?
    private(set) var session: ReviewSession?
    private(set) var phase: Phase = .empty
    /// When the rows were looked up, for the line over a last-known list.
    private(set) var asOf: Date?
    @ObservationIgnored private var loadedFor: UUID?

    /// The preview this screen shows: one still running or recent enough to be reviewed.
    func adopt(_ store: JobStore, kind: JobKind) {
        guard job == nil, let found = store.adoptable(kind: kind, intents: [.preview]) else { return }
        job = found
        loadedFor = nil
        refreshPhase()
    }

    func startPreview(_ store: JobStore, kind: JobKind, options: JobOptions) {
        discard(store)
        job = store.enqueue(JobRequest(kind: kind, intent: .preview, options: options), trigger: .user)
        loadedFor = nil
        refreshPhase()
    }

    /// The setting (Daily/Deep, Trash/permanent) the screen shows, words and previews with. It comes
    /// from the preview on screen, else from the logged preview shown read-only, and only with
    /// neither from the person's own pick (`StorageSetting`).
    func setting(kind: JobKind, chosen: JobOptions) -> JobOptions {
        StorageSetting.shown(kind: kind, preview: job?.request.options,
                             lastKnownBanner: phase == .lastKnown ? block?.banner : nil, chosen: chosen)
    }

    /// The person picked a setting in the menu. When it is not the one on screen, the preview
    /// (or last-known list) was made with the other one: it is put away, as a mode change always has.
    /// Returns whether anything changed.
    @discardableResult
    func pick(_ picked: JobOptions, kind: JobKind, chosen: JobOptions, _ store: JobStore) -> Bool {
        guard StorageSetting.isChange(kind: kind, shown: setting(kind: kind, chosen: chosen), picked: picked) else { return false }
        discard(store)
        return true
    }

    /// Forgets the preview on screen (the options changed, or a new preview starts).
    func discard(_ store: JobStore) {
        store.dismiss(job)
        job = nil; block = nil; rows = nil; session = nil; loadedFor = nil; asOf = nil
        phase = .empty
    }

    /// Where the preview is now; the screen calls this whenever the job's stage changes.
    func refreshPhase() {
        // no preview: the last known list stays, and so does an example review (`showFixture`)
        guard let job else { if phase != .lastKnown, !(phase == .ready && session != nil) { phase = .empty }; return }
        switch job.state {
        case .queued, .running: phase = .running
        case .failed(let failure): phase = .failed(failure.message)
        case .cancelled: phase = .stopped
        case .succeeded:
            if rows == nil, phase != .loading { phase = .loading }
            if rows != nil, loadedFor == job.id { phase = .ready }
        }
    }

    /// Reads the finished preview's whole run and builds the rows and the session. Off the main
    /// actor; called again whenever the job changes stage, and does nothing twice for one job.
    func load(kind: JobKind, parse: @escaping @Sendable (WholeRun.Block) -> StorageRows,
              reviewRow: @escaping (StorageRow) -> ReviewRow) async {
        guard let job, case .succeeded(let outcome) = job.state, loadedFor != job.id else {
            return
        }
        if case .newestFallback(let why) = outcome.match {
            phase = .unreadable(why)
            return
        }
        let banner = job.runHeader, began = job.startedAt, id = job.id
        phase = .loading
        let found = await Task.detached(priority: .userInitiated) { () -> (WholeRun.Block, StorageRows)? in
            guard let banner, let block = StorageLog.block(banner: banner, of: kind, notBefore: began) else { return nil }
            return (block, parse(block))
        }.value
        // the person may have started another preview while this read
        guard self.job?.id == id else { return }
        guard let (block, rows) = found else {
            phase = .unreadable("This preview's own results couldn't be found in the log.")
            return
        }
        self.block = block
        self.rows = rows
        session = ReviewSession(previewID: id, rows: rows.rows.map(reviewRow))
        loadedFor = id
        asOf = job.finishedAt
        phase = .ready
    }

    /// Example rows for looking at a screen headless (`SnapshotRunner`): the review is open, with
    /// no preview behind it, so Apply stays dimmed and nothing can be applied.
    func showFixture(_ fixture: StorageRows) {
        rows = fixture
        session = ReviewSession(previewID: UUID(), rows: fixture.rows.map(\.reviewRow), ticks: ReviewTickStore())
        asOf = Date()
        phase = .ready
    }

    /// With no preview of its own, the screen shows what the newest preview in the log found,
    /// read-only, so it opens on something real.
    /// `matches` says whether that preview is of what the screen is set to now (Daily or Deep,
    /// Trash or permanent): rows of the other setting would be a different list under this title.
    func loadLastKnown(kind: JobKind, matches: @escaping @Sendable (WholeRun.Block) -> Bool = { _ in true },
                       parse: @escaping @Sendable (WholeRun.Block) -> StorageRows,
                       reviewRow: @escaping (StorageRow) -> ReviewRow) async {
        guard job == nil, rows == nil else { return }
        let found = await Task.detached(priority: .userInitiated) { () -> (WholeRun.Block, StorageRows)? in
            guard let block = StorageLog.newestPreview(of: kind), matches(block) else { return nil }
            return (block, parse(block))
        }.value
        guard job == nil, rows == nil, let (block, rows) = found, !rows.rows.isEmpty else { return }
        self.block = block
        self.rows = rows
        session = ReviewSession(readOnly: rows.rows.map(reviewRow))
        asOf = RunDate.date(of: block.banner)
        phase = .lastKnown
    }
}
