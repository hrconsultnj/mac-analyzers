import Foundation
import AnalyzersKit

/// The ACP engines: they drive the person's own Claude Code / Codex
/// binaries through the official Agent Client Protocol adapters. The vendor's
/// binary owns the login — Sparehold never sees a token, never offers a
/// sign-in form, and says so on its cards ("sign-in happens in Claude Code,
/// never here"). The app owns supervision only: the session's default
/// posture is read-only, and anything consequential the agent wants arrives
/// as `session/request_permission`, which maps onto the same permission
/// round-trip the on-device engine uses.
///
/// No fs/write capability is ever advertised (see `ACPClient`'s session
/// handshake), so the adapter cannot ask the app to write files.
public struct ClaudeACPEngine: AgentEngine {

    public var displayName: String { "Claude Code" }

    public init() {}

    public func makeSession(configuration: AgentSessionConfig) -> AgentSession {
        ACPSession(configuration: configuration, adapter: .claude)
    }
}

public struct CodexACPEngine: AgentEngine {

    public var displayName: String { "Codex" }

    public init() {}

    public func makeSession(configuration: AgentSessionConfig) -> AgentSession {
        ACPSession(configuration: configuration, adapter: .codex)
    }
}

/// Which adapter to spawn, and what it needs. Both ride `npx`; the vendor
/// packages are the Agent Client Protocol project's own.
enum ACPAdapter: Sendable {
    case claude
    case codex

    var package: String {
        switch self {
        case .claude: "@agentclientprotocol/claude-agent-acp"
        case .codex: "@agentclientprotocol/codex-acp"
        }
    }

    /// The vendor binary whose auth the adapter uses, for the failure
    /// sentences and the sign-in handoff.
    var vendorBinaryName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    var vendorSignInSentence: String {
        switch self {
        case .claude:
            "Sign-in happens in Claude Code, never here. Open Claude Code in a terminal from the Agents settings screen and sign in there."
        case .codex:
            "Sign-in happens in Codex, never here. Open Codex in a terminal from the Agents settings screen and sign in there (ChatGPT account or OpenAI API key)."
        }
    }
}

/// One ACP conversation: spawns the adapter, negotiates initialize →
/// session/new, picks the safest mode the agent offers, and translates
/// `session/update` traffic into `AgentEvent`s. Permission requests map onto
/// the app's preview round-trip; `fs/read_text_file` is answered for saved
/// reports only, and nothing else.
public actor ACPSession: AgentSession {

    private let configuration: AgentSessionConfig
    private let adapter: ACPAdapter

    private let stream: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation

    private var connection: ACPConnection?
    private var sessionID: String?
    private var started = false
    private var streamFinished = false
    private var turnActive = false

    /// The permission request in flight: what the app shows, and the
    /// continuation `respond` resumes.
    private struct AwaitingPermission {
        let request: AgentPermissionRequest
        let allowOptionID: String?
        let rejectOptionID: String?
        let continuation: CheckedContinuation<(approved: Bool, actions: [String]), Never>
    }
    private var awaitingPermission: AwaitingPermission?

    /// Tool-call ids to titles, so `tool_call_update` can finish the step it
    /// started.
    private var stepTitles: [String: String] = [:]
    /// Plan entries already announced as started, so a plan update finishes
    /// them instead of starting them twice.
    private var openPlanSteps: Set<String> = []

    init(configuration: AgentSessionConfig, adapter: ACPAdapter) {
        self.configuration = configuration
        self.adapter = adapter
        var continuation: AsyncStream<AgentEvent>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public nonisolated var events: AsyncStream<AgentEvent> { stream }

    // MARK: - a turn

    public func send(_ text: String) async {
        guard !turnActive, !streamFinished else { return }
        turnActive = true
        do {
            try await ensureStarted()
        } catch {
            turnActive = false
            finish(.failed(plain(error)))
            return
        }
        let prompt = conversationPrompt(userText: text)
        do {
            let result = try await connection?.request("session/prompt", .object([
                "sessionId": .string(sessionID ?? ""),
                "prompt": .array([.object(["type": .string("text"), "text": .string(prompt)])]),
            ]))
            let stopReason = result?.stringFields["stopReason"] ?? "end_turn"
            turnActive = false
            finish(stopReason == "cancelled" || stopReason == "canceled" ? .cancelled : .completed)
        } catch is CancellationError {
            turnActive = false
            yield(.messageChunk("Stopped."))
            finish(.cancelled)
        } catch {
            turnActive = false
            finish(.failed(plain(error)))
        }
    }

    public func respond(to requestID: UUID, approved: Bool, approvedActions: [String]) async {
        guard !streamFinished, let waiting = awaitingPermission, waiting.request.id == requestID else {
            return
        }
        // The approved set can only shrink: an answer naming something that
        // was not proposed is an escalation, not an approval.
        let valid = approvedActions.allSatisfy { waiting.request.proposedActions.contains($0) }
        awaitingPermission = nil
        guard valid else {
            waiting.continuation.resume(returning: (false, []))
            yield(.messageChunk("That approval named actions that were not proposed, so the request was denied."))
            return
        }
        waiting.continuation.resume(returning: (approved, approvedActions))
    }

    public func cancel() async {
        if let sessionID {
            await connection?.notify("session/cancel", .object(["sessionId": .string(sessionID)]))
        }
        await connection?.stop()
        connection = nil
        guard !streamFinished else { return }
        if turnActive {
            // `session/prompt` fails or returns with the cancelled stop
            // reason; if the connection died first, its pending request fails
            // with the same sentence either way.
            return
        }
        finish(.cancelled)
    }

    /// Ends the session and terminates the adapter process tree.
    func quit() async {
        await connection?.stop()
        connection = nil
        finish(.cancelled)
    }

    // MARK: - starting

    /// initialize → session/new → the safest mode the agent offers. The
    /// client advertises fs READ ONLY and no write: the adapter can ask the
    /// app to read saved reports, never to write anything.
    private func ensureStarted() async throws {
        guard !started else { return }
        guard let npx = EngineInstall.locate("npx") else {
            throw ACPRequestError(code: -1, message: "Node.js and npx are needed to run \(adapter.vendorBinaryName) with Sparehold. Install Node.js (nodejs.org), then the \(adapter.vendorBinaryName) CLI, and it will work from here.")
        }
        let connection = ACPConnection(spec: ACPSpawnSpec(
            executable: URL(fileURLWithPath: npx),
            arguments: ["-y", adapter.package],
            workingDirectory: configuration.workingDirectory))
        await connection.setHandlers(
            onNotification: { [weak self] method, params in
                await self?.handleNotification(method: method, params: params)
            },
            onRequest: { [weak self] method, params in
                guard let self else {
                    return .failure(ACPRequestError(code: -1, message: "The session is gone."))
                }
                return await self.handleRequest(method: method, params: params)
            })
        try await connection.start()
        self.connection = connection

        // The payloads are bound to typed locals: the solver loses the literal
        // type across the cross-actor call when the dictionary nests this deep.
        let capabilities: JSON = .object([
            "fs": .object([
                "readTextFile": .bool(true),
                "writeTextFile": .bool(false),
            ]),
        ])
        let initialize: JSON = .object([
            "protocolVersion": .int(1),
            "clientCapabilities": capabilities,
        ])
        _ = try await connection.request("initialize", initialize)

        let sessionNewParams: JSON = .object([
            "cwd": .string(configuration.workingDirectory.path),
            "mcpServers": .array([]),
        ])
        let created = try await connection.request("session/new", sessionNewParams)
        sessionID = created.stringFields["sessionId"]
        started = true
        await selectSafestMode(created)
    }

    /// Read-only posture for Sparehold sessions: when the agent offers
    /// modes, pick the safest read-only one it names (the vendor keeps its
    /// own mode vocabulary — "plan", "read-only" — and we accept any of
    /// those spellings).
    private func selectSafestMode(_ created: JSON) async {
        guard let sessionID, case .object(let object) = created,
              case .object(let modes) = object["modes"] ?? .null else { return }
        let available = (modes["available"] ?? .array([])).listOfStrings.isEmpty
            ? modeIDs(from: modes["available"] ?? .array([]))
            : []
        let preference = ["read-only", "readonly", "read_only", "plan"]
        for wanted in preference {
            if let match = available.first(where: { $0.localizedCaseInsensitiveContains(wanted) }) {
                await connection?.notify("session/set_mode", .object([
                    "sessionId": .string(sessionID),
                    "modeId": .string(match),
                ]))
                return
            }
        }
    }

    /// The mode ids in the `modes.available` list (each `{id, name,…}`).
    private func modeIDs(from list: JSON) -> [String] {
        guard case .array(let items) = list else { return [] }
        return items.compactMap { item in
            guard case .object(let object) = item else { return nil }
            return object["id"]?.stringValue
        }
    }

    // MARK: - the prompt

    /// The vendor owns its system prompt; Sparehold's rules travel in the
    /// first message: the person's own instructions, the capability line,
    /// and the read-only posture.
    private func conversationPrompt(userText: String) -> String {
        var lines: [String] = []
        if !configuration.prelude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("The person's own instructions for every answer:")
            lines.append(configuration.prelude)
        }
        lines.append("Capabilities switched on for this session: \(configuration.enabledCapabilities.sorted().joined(separator: ", ")). Anything outside them, the client will refuse.")
        lines.append("Posture: read-only. Propose changes as a plan for the person to approve; never imply something was changed before an explicit approval.")
        lines.append("")
        lines.append(userText)
        return lines.joined(separator: "\n")
    }

    // MARK: - session/update → AgentEvent

    private func handleNotification(method: String, params: JSON) async {
        guard method == "session/update", case .object(let object) = params,
              case .object(let update) = object["update"] ?? .null else { return }
        switch update["sessionUpdate"]?.stringValue ?? "" {
        case "agent_message_chunk":
            if let text = text(of: update["contentBlock"] ?? update["content"] ?? .null) {
                yield(.messageChunk(text))
            }
        case "agent_thought_chunk":
            if let text = text(of: update["contentBlock"] ?? update["content"] ?? .null) {
                yield(.thoughtChunk(text))
            }
        case "plan":
            handlePlan(update["entries"] ?? .array([]))
        case "tool_call":
            let id = update["toolCallId"]?.stringValue ?? ""
            let title = update["title"]?.stringValue ?? "Working"
            stepTitles[id] = title
            yield(.stepStarted(name: title, detail: Self.toolDetail(of: .object(update))))
        case "tool_call_update":
            let id = update["toolCallId"]?.stringValue ?? ""
            let status = update["status"]?.stringValue ?? ""
            if status == "completed" || status == "failed", let title = stepTitles.removeValue(forKey: id) {
                yield(.stepFinished(name: title))
            }
        default:
            break
        }
    }

    /// What a tool card shows under the tool's name: the command, path or
    /// address the tool call actually carried (its `rawInput`), not the bare
    /// kind ("execute") — the card is the person's window into the work.
    static func toolDetail(of update: JSON) -> String {
        guard case .object(let outer) = update, case .object(let raw) = outer["rawInput"] ?? .null else { return "" }
        for key in ["command", "path", "file_path", "url", "query", "pattern"] {
            if let text = raw[key]?.stringValue, !text.isEmpty { return text }
        }
        // no known key: the first string field, kept short
        for (_, value) in raw.sorted(by: { $0.key < $1.key }) {
            if let text = value.stringValue, !text.isEmpty, text.count <= 120 { return text }
        }
        return ""
    }

    /// A plan update carries the WHOLE plan each time: an entry that has
    /// started is a step started; one now completed finishes its step.
    private func handlePlan(_ entries: JSON) {
        guard case .array(let items) = entries else { return }
        var completed: Set<String> = []
        for item in items {
            guard case .object(let entry) = item else { continue }
            let title = entry["content"]?.stringValue ?? entry["title"]?.stringValue ?? ""
            guard !title.isEmpty else { continue }
            let status = entry["status"]?.stringValue ?? "pending"
            if status == "completed" || status == "done" {
                completed.insert(title)
                if openPlanSteps.contains(title) {
                    openPlanSteps.remove(title)
                    yield(.stepFinished(name: title))
                }
            } else if status != "pending", !openPlanSteps.contains(title) {
                openPlanSteps.insert(title)
                yield(.stepStarted(name: title, detail: "plan"))
            }
        }
        // An entry that vanished from the plan was dropped by the agent;
        // finish its step so the screen is not left with an open step.
        for title in openPlanSteps where completed.contains(title) {
            openPlanSteps.remove(title)
            yield(.stepFinished(name: title))
        }
    }

    /// The text of a content block (`{type: "text", text: …}`).
    private func text(of block: JSON) -> String? {
        guard case .object(let object) = block else { return nil }
        return object["text"]?.stringValue
    }

    // MARK: - server→client requests

    private func handleRequest(method: String, params: JSON) async -> Result<JSON, ACPRequestError> {
        switch method {
        case "session/request_permission":
            return await requestPermission(params)
        case "fs/read_text_file":
            return readReportFile(params)
        default:
            return .failure(ACPRequestError(code: -32601, message: "Not supported: \(method)"))
        }
    }

    /// `session/request_permission` → the app's permission round-trip. This
    /// handler suspends inside the connection's read task until the person
    /// answers on the preview screen (`respond` resumes it), then translates
    /// the verdict into the wire answer. A request outside the enabled
    /// capabilities is denied WITHOUT asking — the same gate the on-device
    /// tools apply, so the model reads a denial instead of a silent kill.
    private func requestPermission(_ params: JSON) async -> Result<JSON, ACPRequestError> {
        guard case .object(let object) = params else {
            return .failure(ACPRequestError(code: -32602, message: "Malformed permission request."))
        }
        let toolCall = object["toolCall"] ?? .null
        let title = toolCall.stringFields["title"] ?? "Allow this action"
        let kind = toolCall.stringFields["kind"] ?? ""
        let cancelled = Result<JSON, ACPRequestError>.success(.object(["outcome": .object([
            "outcome": .string("cancelled"),
        ])]))
        if isOutsideCapabilities(kind: kind) {
            return cancelled
        }
        let options = object["options"] ?? .array([])
        let allowOptionID = optionID(in: options, matching: ["allow_once", "allow_always", "allow"])
            ?? firstOptionID(namedLike: ["allow", "yes", "approve"], in: options)
        let rejectOptionID = optionID(in: options, matching: ["reject_once", "reject_always", "reject"])
            ?? firstOptionID(namedLike: ["reject", "deny", "no"], in: options)

        let request = AgentPermissionRequest(title: title, proposedActions: [title])
        let verdict: (approved: Bool, actions: [String]) = await withCheckedContinuation { continuation in
            awaitingPermission = AwaitingPermission(
                request: request, allowOptionID: allowOptionID, rejectOptionID: rejectOptionID,
                continuation: continuation)
            yield(.permissionRequest(request))
        }
        if verdict.approved, let allow = allowOptionID {
            return .success(.object(["outcome": .object([
                "outcome": .string("selected"),
                "optionId": .string(allow),
            ])]))
        }
        if let reject = rejectOptionID {
            return .success(.object(["outcome": .object([
                "outcome": .string("selected"),
                "optionId": .string(reject),
            ])]))
        }
        return cancelled
    }

    /// The exact-match option id for a kind (`allow_once` etc.), or nil.
    private func optionID(in options: JSON, matching kinds: [String]) -> String? {
        guard case .array(let items) = options else { return nil }
        for item in items {
            guard case .object(let object) = item,
                  let kind = object["kind"]?.stringValue,
                  let id = object["optionId"]?.stringValue else { continue }
            if kinds.contains(kind) { return id }
        }
        return nil
    }

    /// The first option whose name or id names one of `words` (vendors that
    /// do not fill `kind` still name their options).
    private func firstOptionID(namedLike words: [String], in options: JSON) -> String? {
        guard case .array(let items) = options else { return nil }
        for item in items {
            guard case .object(let object) = item else { continue }
            let id = object["optionId"]?.stringValue ?? ""
            let name = object["name"]?.stringValue ?? ""
            let text = (id + " " + name).lowercased()
            if words.contains(where: { text.contains($0) }) {
                return id.isEmpty ? nil : id
            }
        }
        return nil
    }

    /// Which tool kinds the capability set does not cover: an ask to edit or
    /// delete anything is the apply-gated capability; an ask to run commands
    /// is the propose/apply pair (a change can only come from them).
    private func isOutsideCapabilities(kind: String) -> Bool {
        let lowered = kind.lowercased()
        let enabled = configuration.enabledCapabilities
        switch lowered {
        case "edit", "delete", "write":
            return !enabled.contains("startApprovedCleans")
        case "execute", "command", "terminal":
            return !enabled.contains("proposeCleanups") && !enabled.contains("startApprovedCleans")
        default:
            return false
        }
    }

    /// `fs/read_text_file` — saved reports only, and only when the
    /// capability allows reading them. Everything else is an error the
    /// agent reads.
    private func readReportFile(_ params: JSON) -> Result<JSON, ACPRequestError> {
        guard configuration.enabledCapabilities.contains("readReports") else {
            return .failure(ACPRequestError(code: -1, message: "Reading files is switched off for this session (Settings › Agents › Capabilities). Answer from the conversation instead."))
        }
        guard let rawPath = params.stringFields["path"] else {
            return .failure(ACPRequestError(code: -32602, message: "A path is required."))
        }
        let reports = AnalyzersPaths.userReports.standardizedFileURL
        let path = URL(fileURLWithPath: rawPath).standardizedFileURL
        guard path.path.hasPrefix(reports.path + "/") else {
            return .failure(ACPRequestError(code: -1, message: "Only saved Sparehold reports can be read here (under \(AnalyzersPaths.displayPath(AnalyzersPaths.userReports)))."))
        }
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            return .failure(ACPRequestError(code: -1, message: "That report could not be read."))
        }
        return .success(.object(["content": .string(String(text.prefix(20_000)))]))
    }

    // MARK: - small helpers

    private func yield(_ event: AgentEvent) {
        guard !streamFinished else { return }
        continuation.yield(event)
    }

    private func finish(_ reason: AgentStopReason) {
        guard !streamFinished else { return }
        streamFinished = true
        if let waiting = awaitingPermission {
            awaitingPermission = nil
            waiting.continuation.resume(returning: (false, []))
        }
        continuation.yield(.done(reason))
        continuation.finish()
    }

    /// The vendor owns the model choice: no model is ever pinned here, so the
    /// CLI's default follows its version and the subscription — always the
    /// latest. A config that pins an unsupported model still surfaces the
    /// vendor's error, with the fix attached.
    static func withModelHint(_ message: String) -> String {
        guard message.contains("not supported when using Codex with a ChatGPT account") else { return message }
        return message + " Update Codex (codex update) — the model your subscription offers follows the CLI version."
    }

    private func plain(_ error: Error) -> String {
        let text: String
        if let acpError = error as? ACPRequestError { text = acpError.message }
        else { text = error.localizedDescription }
        return Self.withModelHint(text)
    }
}
