import Foundation

/// The one seam every agent engine speaks. Two implementations are planned:
/// the on-device MLX engine (`LocalEngine`) and the ACP engines that drive the
/// user's own Claude Code / Codex binaries (`ACPEngines`). A session is one
/// conversation; the app owns supervision — an engine proposes, the reviewed
/// scripts execute, and nothing the engine says is trusted with more than the
/// capability set in `AgentTunables`.
///
/// The protocol is engine-agnostic on purpose: the Ask screens are built
/// against it (and `MockEngine`), so the UI never knows which engine answered.
public protocol AgentEngine: Sendable {
    /// A human name for the engine, for the session log and Activity.
    var displayName: String { get }
    func makeSession(configuration: AgentSessionConfig) -> AgentSession
}

/// One agent conversation. `send` starts a turn; everything the engine does
/// arrives as `events`. A turn ends with `.done`, which always comes — an
/// engine that cannot finish still reports a failure, so a session never
/// hangs silently.
public protocol AgentSession: Sendable {
    /// Every step, message chunk and permission request, in order. Consumed
    /// from one task (the Ask session's); the stream finishes with the turn.
    var events: AsyncStream<AgentEvent> { get }
    /// Send one user message and run a turn. One turn at a time: a second
    /// call before `.done` is a programming error (the UI prevents it).
    func send(_ text: String) async
    /// The answer to a permission request (S3: the preview screen's verdict).
    /// `approved` carries the shrunken set — it can only ever be smaller than
    /// what was proposed.
    func respond(to requestID: UUID, approved: Bool, approvedActions: [String]) async
    /// Stop the turn at the next boundary. Best effort: an engine cancels its
    /// child process / generation and then reports `.done(.cancelled)`.
    func cancel() async
}

/// How an engine is configured at session start.
public struct AgentSessionConfig: Sendable {
    /// The working directory the engine's tools run in.
    public var workingDirectory: URL
    /// The capability ids the session may use (from `AgentTunables`).
    public var enabledCapabilities: Set<String>
    /// The user's own extra instructions (`AGENT_PRELUDE`).
    public var prelude: String

    public init(workingDirectory: URL, enabledCapabilities: Set<String>, prelude: String = "") {
        self.workingDirectory = workingDirectory
        self.enabledCapabilities = enabledCapabilities
        self.prelude = prelude
    }
}

/// Everything an engine says, in order. One enum so the consumer's switch
/// stays exhaustive when engines grow new steps.
public enum AgentEvent: Sendable, Equatable {
    /// A named step started ("ran the storage scan"). The detail names the
    /// real script or tool, so the Working screen can show it verbatim.
    case stepStarted(name: String, detail: String)
    case stepFinished(name: String)
    /// A piece of the agent's reply. Chunks concatenate in order.
    case messageChunk(String)
    /// A piece of the agent's reasoning, kept apart from the answer — the
    /// session shows it in its own place, never mixed into the reply.
    case thoughtChunk(String)
    /// The engine proposes consequential actions; the user answers through
    /// the preview screen. See `AgentPermissionRequest`.
    case permissionRequest(AgentPermissionRequest)
    case done(AgentStopReason)
}

/// Why a turn ended. `completed` is the good case; everything else says why
/// in words the app can show without translation.
public enum AgentStopReason: Sendable, Equatable {
    case completed
    case cancelled
    case failed(String)
}

/// One permission round-trip: the engine proposes a set of consequential
/// actions, the app renders them as the existing preview screen (grouped,
/// ticked, sizes), and the user's verdict returns through
/// `AgentSession.respond`. The approved set can only ever shrink — the UI
/// enforces that, exactly as the manual preview does. No engine is ever
/// handed an approval that includes something it did not propose.
public struct AgentPermissionRequest: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// One line ("Free up space in Downloads"), for the preview screen's header.
    public let title: String
    /// The proposed actions, each a stable identifier the engine's tools
    /// understand ("cleaner:downloads-janitor", "setting:janitorDownloadsDays=14").
    public let proposedActions: [String]

    public init(title: String, proposedActions: [String]) {
        self.id = UUID()
        self.title = title
        self.proposedActions = proposedActions
    }
}

/// A scripted engine for previews, SnapshotRunner renders and UI work that
/// runs before the real engines land. It replays a fixed five-beat session
/// (scan → read → propose → reply) so every screen has something honest to
/// show. It performs no tool and changes nothing.
public struct MockEngine: AgentEngine {
    public var displayName: String { "Preview Engine" }

    public init() {}

    public func makeSession(configuration: AgentSessionConfig) -> AgentSession {
        MockSession(configuration: configuration)
    }
}

/// The scripted session behind `MockEngine`.
public struct MockSession: AgentSession {
    let configuration: AgentSessionConfig
    let stream: AsyncStream<AgentEvent>
    let continuation: AsyncStream<AgentEvent>.Continuation

    public var events: AsyncStream<AgentEvent> { stream }

    init(configuration: AgentSessionConfig) {
        self.configuration = configuration
        var continuation: AsyncStream<AgentEvent>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func send(_ text: String) async {
        let steps: [(String, String)] = [
            ("Checking what asked for", text),
            ("Running the storage scan", "analyze.sh --brief"),
            ("Reading the report", "reports/storage/analyze.json"),
            ("Checking the protected list", "lib/approved-list.sh"),
        ]
        for (name, detail) in steps {
            continuation.yield(.stepStarted(name: name, detail: detail))
            try? await Task.sleep(for: .milliseconds(300))
            continuation.yield(.stepFinished(name: name))
        }
        continuation.yield(.messageChunk("Nothing has been changed. Here is what I would do:"))
        let request = AgentPermissionRequest(
            title: "Free up space (preview)",
            proposedActions: ["cleaner:downloads-janitor", "cleaner:temp-clean"])
        continuation.yield(.permissionRequest(request))
        continuation.yield(.done(.completed))
        continuation.finish()
    }

    public func respond(to requestID: UUID, approved: Bool, approvedActions: [String]) async {
        continuation.yield(.messageChunk(approved ? "Approved \(approvedActions.count) of the proposed actions." : "Nothing will be changed."))
        continuation.yield(.done(approved ? .completed : .cancelled))
        continuation.finish()
    }

    public func cancel() async {
        continuation.yield(.done(.cancelled))
        continuation.finish()
    }
}

/// The "bring your own" engine before its wiring exists: every turn answers
/// with the sentence a person can act on, and changes nothing. Custom ACP
/// spawning arrives with the registry fast-follow (DEC-08).
public struct UnwiredEngine: AgentEngine {
    public var displayName: String { "Custom engine" }
    public init() {}

    public func makeSession(configuration: AgentSessionConfig) -> AgentSession {
        UnwiredSession()
    }
}

/// The sentence-bearing session behind `UnwiredEngine`.
struct UnwiredSession: AgentSession {
    let stream: AsyncStream<AgentEvent>
    let continuation: AsyncStream<AgentEvent>.Continuation

    init() {
        var continuation: AsyncStream<AgentEvent>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public var events: AsyncStream<AgentEvent> { stream }

    public func send(_ text: String) async {
        continuation.yield(.messageChunk("The custom engine isn't wired in this build yet. Choose On-Device, Claude Code or Codex in Settings › Agents and ask again."))
        continuation.yield(.done(.completed))
        continuation.finish()
    }

    public func respond(to requestID: UUID, approved: Bool, approvedActions: [String]) async {}

    public func cancel() async {
        continuation.yield(.done(.cancelled))
        continuation.finish()
    }
}
