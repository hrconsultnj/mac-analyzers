import Foundation
import Observation
import AnalyzersKit

/// One Ask conversation's state (S2's view model): the turns so far — each
/// with the question, the steps streaming in from the engine, the reply as it
/// grows, and how the turn ended — plus the turn in flight. A finished turn is
/// archived into the conversation and the input stays live: a chat you can
/// scroll back through is a chat you can keep talking to.
///
/// Every conversation persists to `AskHistoryStore` on each turn's end, so the
/// history list on the Ask home can reopen it, and a reopened conversation can
/// continue where it left off.
///
/// The session consumes an `AgentSession`'s `AsyncStream<AgentEvent>` from one
/// task and translates events into view state; it never calls a cleaner
/// itself. The turn's scan beat is a tracked job from the ONE `JobStore` (the
/// AGENTS.md rule), so Activity lists every run and the toolbar strip shows it
/// while it goes.
///
/// The permission round-trip: on `.permissionRequest` the turn holds the
/// proposed actions and enters `.awaitingApproval`; the screen renders them as
/// a tick list that can only shrink, and the verdict returns through
/// `AgentSession.respond` — the engine is never handed more than it proposed.
/// A `.done` that arrives while a request is still open is HELD (the engine is
/// waiting on the person, not finished); the turn ends when the verdict is in.
@MainActor @Observable
public final class AskSession {

    /// What the conversation is doing. `.idle` means every turn is archived
    /// and the next message starts a fresh one.
    public enum Phase: Equatable {
        case idle
        case working
        case awaitingApproval
        case done
    }

    /// One named step of the loop, naming the real script it ran.
    public struct Step: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        /// The script or tool the step named, shown verbatim ("analyze.sh --brief").
        public let detail: String
        public var finished: Bool
    }

    /// What a finished cleanup leaves (S4). `freedLine` is the byte sentence
    /// ("41 GB → 44.9 GB free") once an engine can measure it; the v1 preview
    /// engine runs nothing, so the outcome is the verdict itself.
    public struct Receipt: Equatable, Sendable {
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

    /// The conversation's identity and its turns, oldest first. `turns` holds
    /// every FINISHED turn; the live one is the flat fields below.
    public let id: UUID
    public let started: Date
    public private(set) var turns: [AskTurn] = []

    public private(set) var phase: Phase = .working
    /// The user's message that started the live turn.
    public private(set) var prompt: String = ""
    public private(set) var steps: [Step] = []
    /// The agent's reasoning, kept apart from the answer.
    public private(set) var thinking: String = ""
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
    /// The engine — and model, when one is loaded — answering the live turn.
    public private(set) var engineTitle: String = ""

    @ObservationIgnored private var agentSession: (any AgentSession)?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    /// A `.done` held back because a permission request was still open.
    @ObservationIgnored private var heldStop: AgentStopReason?
    @ObservationIgnored private var streamFinished = false
    @ObservationIgnored private var approvedActions: [String]?
    @ObservationIgnored private var proposedCount = 0
    @ObservationIgnored private var beganAt = Date()
    @ObservationIgnored private var scanIsPending = false

    private init(id: UUID, started: Date) {
        self.id = id
        self.started = started
    }

    /// Starts a conversation with one turn: one user message, its scan as a
    /// tracked job, and the engine's stream consumed into this state.
    @discardableResult
    public static func begin(prompt: String, scan: (kind: JobKind, intent: JobIntent)?,
                             config: AgentSessionConfig, jobs: JobStore) -> AskSession {
        let ask = AskSession(id: UUID(), started: Date())
        ask.appendTurnEngine(prompt: prompt, scan: scan, config: config, jobs: jobs)
        AskHistoryStore.shared.loadIfNeeded()
        return ask
    }

    /// Reopens a saved conversation. Nothing runs: every turn is archived, the
    /// phase is idle, and the next message continues THIS conversation (same
    /// id, same history file).
    @discardableResult
    public static func reopened(from conversation: AskConversation) -> AskSession {
        let ask = AskSession(id: conversation.id, started: conversation.started)
        ask.turns = conversation.turns
        ask.phase = .idle
        AskHistoryStore.shared.loadIfNeeded()
        return ask
    }

    /// Starts a turn in THIS conversation — the input's one door, live while a
    /// turn is not already running. The scan beat applies only to the very
    /// first turn (a follow-up question answers from what is already known).
    public func send(_ text: String, scan: (kind: JobKind, intent: JobIntent)?,
                     config: AgentSessionConfig, jobs: JobStore) {
        guard phase == .idle || phase == .done else { return }
        appendTurnEngine(prompt: text, scan: turns.isEmpty ? scan : nil, config: config, jobs: jobs)
    }

    /// The shared turn machinery: archive anything live, reset the flat
    /// fields, wire a fresh engine, enqueue the scan, and consume the stream.
    private func appendTurnEngine(prompt: String, scan: (kind: JobKind, intent: JobIntent)?,
                                  config: AgentSessionConfig, jobs: JobStore) {
        archiveLiveTurn()
        self.prompt = prompt
        steps = []
        thinking = ""
        reply = ""
        request = nil
        ticked = []
        receipt = nil
        stopped = false
        failure = nil
        heldStop = nil
        approvedActions = nil
        proposedCount = 0
        beganAt = Date()
        streamFinished = false
        phase = .working
        if let scan {
            // The loop's scan beat: the read-only analyzer the turn names, in
            // the one engine lane. Previews for cleaners (dry run), `.run` for
            // the analyzers — never an apply.
            job = jobs.enqueue(JobRequest(kind: scan.kind, intent: scan.intent), trigger: .user)
            scanIsPending = true
        } else {
            job = nil
            scanIsPending = false
        }
        let engine = Self.makeEngine(jobStore: jobs)
        let session = engine.makeSession(configuration: config)
        agentSession = session
        engineTitle = Self.engineLabel()
        consumeTask?.cancel()
        consumeTask = Task { [weak self] in
            for await event in session.events {
                self?.apply(event)
            }
            self?.streamDidFinish()
        }
        Task { await session.send(prompt) }
        persist()
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

    /// The name the reply is labelled with: the engine, and the model when
    /// one is loaded — a person reads which intelligence answered, never a
    /// bare product name.
    private static func engineLabel() -> String {
        switch ConfigStore.currentAgentEngine() {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        case "custom": return "Custom engine"
        default:
            let model = ConfigStore.currentAgentModelID()
            let name = model.split(separator: "/").last.map(String.init) ?? model
            return name.isEmpty ? "Sparehold On-Device" : "Sparehold On-Device · \(name)"
        }
    }

    /// Stops the turn at the engine's next boundary. Nothing has been changed
    /// by a stopped turn — the standing line stays true. A Stop also answers
    /// an open permission request: nothing was approved, so nothing runs.
    public func stop() {
        guard phase != .done, phase != .idle else { return }
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
        case .thoughtChunk(let chunk):
            thinking += chunk
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
        guard phase != .done, phase != .idle else { return }
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
                    // (the reviewed preview wires it); the preview engine runs
                    // nothing and says so.
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
        persist()
    }

    // MARK: - persistence

    /// Archives the live turn into `turns` and saves the conversation. Called
    /// at a turn's start (so an in-flight quit still leaves the question) and
    /// at its end.
    private func archiveLiveTurn() {
        guard !prompt.isEmpty else { return }
        let turn = AskTurn(
            prompt: prompt,
            steps: steps.map { AskStepRecord(id: $0.id, name: $0.name, detail: $0.detail, finished: $0.finished) },
            reply: reply,
            thinking: thinking,
            failure: failure,
            stopped: stopped,
            receiptHeadline: receipt?.headline)
        turns.append(turn)
        prompt = ""
    }

    private func persist() {
        var saved = turns
        // The live turn saves too, so a quit mid-turn keeps the question and
        // whatever had streamed; its live state re-archives on the next turn.
        if !prompt.isEmpty {
            saved.append(AskTurn(
                prompt: prompt,
                steps: steps.map { AskStepRecord(id: $0.id, name: $0.name, detail: $0.detail, finished: $0.finished) },
                reply: reply,
                thinking: thinking,
                failure: failure,
                stopped: stopped,
                receiptHeadline: receipt?.headline))
        }
        AskHistoryStore.shared.save(AskConversation(id: id, started: started, turns: saved))
    }
}
