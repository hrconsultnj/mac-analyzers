import Foundation
import Observation
import AnalyzersKit

/// One Ask conversation's state (S2's view model): the user's message, the
/// steps streaming in from the engine, the reply as it grows, the permission
/// round-trip, and the receipt a finished cleanup leaves.
///
/// The session consumes an `AgentSession`'s `AsyncStream<AgentEvent>` from one
/// task and translates events into view state; it never calls a cleaner
/// itself. The turn's scan beat is a tracked job from the ONE `JobStore` (the
/// AGENTS.md rule), so Activity lists every run and the toolbar strip shows it
/// while it goes.
///
/// The permission round-trip: on `.permissionRequest` the session holds the
/// proposed actions and enters `.awaitingApproval`; the screen renders them as
/// a tick list that can only shrink, and the verdict returns through
/// `AgentSession.respond` — the engine is never handed more than it proposed.
/// A `.done` that arrives while a request is still open is HELD (the engine is
/// waiting on the person, not finished); the turn ends when the verdict is in.
@MainActor @Observable
public final class AskSession {

    /// What the conversation is doing.
    public enum Phase: Equatable {
        case working
        case awaitingApproval
        case done
    }

    /// One named step of the loop, naming the real script it ran.
    public struct Step: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        /// The script or tool the step named, shown verbatim ("analyze.sh --brief").
        public let detail: String
        public var finished: Bool
    }

    /// What a finished cleanup leaves (S4). `freedLine` is the byte sentence
    /// ("41 GB → 44.9 GB free") once an engine can measure it; the v1 preview
    /// engine runs nothing, so the outcome is the verdict itself.
    public struct Receipt: Equatable {
        /// Outcome first, in the person's terms.
        public let headline: String
        public let freedLine: String?
        public let approvedCount: Int
        public let proposedCount: Int
        /// Rows the protected list held back.
        public let skippedProtected: Int
        /// How long the turn took, whole.
        public let duration: TimeInterval
    }

    public private(set) var phase: Phase = .working
    /// The user's message that started the turn.
    public private(set) var prompt: String = ""
    public private(set) var steps: [Step] = []
    /// The agent's reply, concatenated from the stream's chunks in order.
    public private(set) var reply: String = ""
    /// The open permission request, while the person has not answered.
    public private(set) var request: AgentPermissionRequest?
    /// The ticked subset of `request`'s proposed actions — shrunk by the person.
    public private(set) var ticked: Set<String> = []
    /// Set once the turn ended after an approval; the S4 screen renders it.
    public private(set) var receipt: Receipt?
    /// A Stop, or a Not Now: the turn ended with nothing changed.
    public private(set) var stopped = false
    /// Why a turn failed, when the engine said so.
    public private(set) var failure: String?
    /// The tracked job behind the turn's scan beat. Held, not adopted: the
    /// toolbar strip and Activity read the store.
    public private(set) var job: Job?

    public init() {}

    @ObservationIgnored private var agentSession: (any AgentSession)?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    /// A `.done` held back because a permission request was still open.
    @ObservationIgnored private var heldStop: AgentStopReason?
    @ObservationIgnored private var streamFinished = false
    @ObservationIgnored private var approvedActions: [String]?
    @ObservationIgnored private var proposedCount = 0
    @ObservationIgnored private let beganAt = Date()

    /// Starts a turn: one user message, its scan as a tracked job, and the
    /// engine's stream consumed into this state.
    @discardableResult
    public static func begin(prompt: String, scan: (kind: JobKind, intent: JobIntent)?,
                             config: AgentSessionConfig, jobs: JobStore) -> AskSession {
        let ask = AskSession()
        ask.prompt = prompt
        if let scan {
            // The loop's scan beat: the read-only analyzer the turn names, in
            // the one engine lane. Previews for cleaners (dry run), `.run` for
            // the analyzers — never an apply.
            ask.job = jobs.enqueue(JobRequest(kind: scan.kind, intent: scan.intent), trigger: .user)
        }
        let engine = makeEngine(jobStore: jobs)
        let session = engine.makeSession(configuration: config)
        ask.agentSession = session
        ask.consumeTask = Task { [weak ask] in
            for await event in session.events {
                ask?.apply(event)
            }
            ask?.streamDidFinish()
        }
        Task { await session.send(prompt) }
        return ask
    }

    /// THE ENGINE SEAM: the configured engine (`AGENT_ENGINE`), read the same
    /// way the static config reads work elsewhere. Nothing else in the Ask
    /// surface knows which engine answers.
    private static func makeEngine(jobStore: JobStore) -> any AgentEngine {
        switch ConfigStore.currentAgentEngine() {
        case "claude": ClaudeACPEngine()
        case "codex": CodexACPEngine()
        case "custom": UnwiredEngine()
        default: LocalEngine(jobStore: jobStore)
        }
    }

    /// Stops the turn at the engine's next boundary. Nothing has been changed
    /// by a stopped turn — the standing line stays true. A Stop also answers
    /// an open permission request: nothing was approved, so nothing runs.
    public func stop() {
        guard phase != .done else { return }
        stopped = true
        request = nil
        ticked = []
        if streamFinished {
            // The engine's stream already ended (the v1 scripted session ends
            // it with the permission request): end the turn here.
            finishTurn(.cancelled)
        } else {
            let session = agentSession
            Task { await session?.cancel() }
        }
    }

    /// The person's verdict on the open request: the ticked subset, which can
    /// only be smaller than what was proposed. After it, the engine finishes
    /// the turn (its closing words and `.done` arrive on the stream).
    public func respond(approvedActions: [String]) {
        guard let request, phase == .awaitingApproval else { return }
        self.request = nil
        ticked = []
        proposedCount = request.proposedActions.count
        self.approvedActions = approvedActions
        phase = .working
        let session = agentSession
        let id = request.id
        let approved = approvedActions
        Task { [weak self] in
            await session?.respond(to: id, approved: true, approvedActions: approved)
            // An engine whose stream already ended with the request (the v1
            // scripted session does) never sends another `.done`: finish the
            // turn here. A live engine does its own finishing first.
            if self?.streamFinished == true { self?.finishTurn(.completed) }
        }
    }

    /// Removes one action from the approved set. This is the set's ONLY write:
    /// it starts at everything proposed and can shrink, never grow — the same
    /// invariant the manual preview's ticks carry.
    public func untick(_ action: String) {
        ticked.remove(action)
    }

    /// "Not now": nothing is approved, nothing runs.
    public func decline() {
        guard let request, phase == .awaitingApproval else { return }
        let id = request.id
        self.request = nil
        ticked = []
        approvedActions = []
        proposedCount = 0
        stopped = true
        phase = .working
        let session = agentSession
        Task { [weak self] in
            await session?.respond(to: id, approved: false, approvedActions: [])
            // Same rule as `respond`: an engine that ended its stream with the
            // request never sends another `.done`, so the turn ends here.
            if self?.streamFinished == true { self?.finishTurn(.cancelled) }
        }
    }

    // MARK: - events in

    private func apply(_ event: AgentEvent) {
        switch event {
        case .stepStarted(let name, let detail):
            steps.append(Step(id: UUID(), name: name, detail: detail, finished: false))
        case .stepFinished(let name):
            if let index = steps.lastIndex(where: { !$0.finished && $0.name == name }) {
                steps[index].finished = true
            }
        case .messageChunk(let chunk):
            reply += chunk
        case .permissionRequest(let request):
            self.request = request
            // Everything is proposed: the person unticks to shrink.
            ticked = Set(request.proposedActions)
            phase = .awaitingApproval
        case .done(let reason):
            if request != nil {
                // The engine waits on the person; the turn ends after the
                // verdict, not now.
                heldStop = reason
            } else {
                finishTurn(reason)
            }
        }
    }

    /// The stream ended. With a request still open the verdict still has to
    /// come; anything else is the turn's end.
    private func streamDidFinish() {
        streamFinished = true
        guard request == nil else { return }
        finishTurn(heldStop ?? (stopped ? .cancelled : .completed))
    }

    private func finishTurn(_ reason: AgentStopReason) {
        guard phase != .done else { return }
        phase = .done
        heldStop = nil
        let endedAt = Date()
        switch reason {
        case .completed:
            if let approved = approvedActions {
                receipt = Receipt(
                    headline: approved.isEmpty
                        ? "Nothing was approved, so nothing runs."
                        : "Approved \(approved.count) of \(max(proposedCount, approved.count)) proposed actions.",
                    // The byte sentence arrives with the real engines' apply
                    // (Phase 5 wires the reviewed preview); the v1 preview
                    // engine runs nothing and says so.
                    freedLine: nil,
                    approvedCount: approved.count,
                    proposedCount: proposedCount,
                    skippedProtected: 0,
                    duration: endedAt.timeIntervalSince(beganAt))
            }
        case .cancelled:
            stopped = true
        case .failed(let message):
            failure = message
        }
    }
}
