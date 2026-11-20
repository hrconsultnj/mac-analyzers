import Foundation
import AnalyzersKit
import MLX
// MLXLMCommon predates strict Sendable (Chat.Message crosses into the
// container's perform closure by the library's own design); the preconcurrency
// boundary is the documented integration path, scoped to this one import.
@preconcurrency import MLXLMCommon
import MLXLLM

/// The on-device engine: the model downloaded in On-Device Models runs here,
/// in this process, on this Mac — nothing leaves. The engine is the same
/// bash suite it always was: the model proposes, `AgentTools` runs the
/// reviewed scripts, and an apply exists only through the kernel's preview
/// and approval.
///
/// All MLX work stays inside this actor (and `ModelContainer`, itself an
/// actor): MLXArray and friends are not Sendable, so nothing of the runtime
/// ever crosses a boundary — events, text and tool results do.
public struct LocalEngine: AgentEngine {

    public var displayName: String { "Sparehold On-Device" }

    /// The one job store the app owns; scans and applies queue on its single
    /// engine lane like every other run.
    private let jobStore: JobStore

    public init(jobStore: JobStore) {
        self.jobStore = jobStore
    }

    public func makeSession(configuration: AgentSessionConfig) -> AgentSession {
        LocalSession(configuration: configuration, jobStore: jobStore)
    }
}

/// One on-device conversation. Holds the loaded model, the conversation, and
/// the tool registry's verdicts. Unloads itself after five idle minutes and
/// on the system's memory-pressure warning — a resident model is exactly the
/// pressure the Memory Guard fights, so the engine gives it back on its own.
public actor LocalSession: AgentSession {

    private let configuration: AgentSessionConfig
    private let tools: AgentTools
    private let modelID: String
    private let family: ToolCallFamily
    private let modelDirectory: URL

    private let stream: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation

    /// The conversation, in the model's own message shape. The system prompt
    /// is first and is never trimmed away.
    private var history: [Chat.Message] = []
    /// The loaded model, when one is. Nil after unload.
    private var container: ModelContainer?
    /// The permission requests this session raised, awaiting `respond`.
    private var pendingRequests: [UUID: AgentPermissionRequest] = [:]
    /// The turn in flight, so `cancel` reaches the generation loop.
    private var currentTurn: Task<Void, Never>?
    private var turnActive = false
    private var streamFinished = false

    /// Five minutes after the last turn the model is unloaded.
    private var idleUnloadTask: Task<Void, Never>?
    /// The system's memory-pressure signal, watched while a model is loaded.
    private var pressureSource: DispatchSourceMemoryPressure?

    /// Tool-call loop bound: a model that loops tool calls is stopped after
    /// this many, with the conversation saying so.
    private static let maxToolIterations = 8
    /// Generation bound per step (the person is reading while it streams).
    private static let maxNewTokens = 1_200
    /// Tool results are appended summarized — context discipline is the RAM
    /// and reliability control for a local model.
    private static let toolResultLimit = 1_200
    /// Rough token estimate: about four characters to a token. Deliberately
    /// conservative; smaller is safer than swapping.
    private static let charactersPerToken = 4

    init(configuration: AgentSessionConfig, jobStore: JobStore) {
        self.configuration = configuration
        self.tools = AgentTools(jobStore: jobStore)
        let modelID = ConfigStore.currentAgentModelID()
        self.modelID = modelID
        self.family = ToolCallFamily.forModelID(modelID)
        self.modelDirectory = AnalyzersPaths.modelsDirectory.appending(path: modelID)
        var continuation: AsyncStream<AgentEvent>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    deinit {
        idleUnloadTask?.cancel()
        pressureSource?.cancel()
    }

    public nonisolated var events: AsyncStream<AgentEvent> { stream }

    // MARK: - a turn

    public func send(_ text: String) async {
        guard !turnActive, !streamFinished else { return }
        turnActive = true
        let turn = Task { await self.runTurn(userText: text) }
        currentTurn = turn
        await turn.value
    }

    public func respond(to requestID: UUID, approved: Bool, approvedActions: [String]) async {
        guard !streamFinished, let request = pendingRequests[requestID] else { return }
        pendingRequests[requestID] = nil
        // The approved set can only shrink: an answer naming something that
        // was not proposed is not an answer, it is an escalation.
        let valid = approvedActions.allSatisfy { request.proposedActions.contains($0) }
        guard valid else {
            yield(.messageChunk("That approval named actions that were not proposed, so nothing was applied. Nothing has been changed."))
            finish(.cancelled)
            return
        }
        guard approved, !approvedActions.isEmpty else {
            yield(.messageChunk("Nothing will be changed."))
            finish(.cancelled)
            return
        }
        // The person approved on the preview screen; the apply is the same
        // kernel path a manual Apply takes (`AgentTools.runApprovedCleanup`
        // → `JobStore.apply(from:approved:)`). For kinds whose engine takes a
        // reviewed row list and the round-trip carries none yet (the S3
        // preview handoff), the kernel itself refuses and the refusal is what
        // the model and the person read — never a silent wide apply.
        yield(.stepStarted(name: "Applying what was approved", detail: "JobStore.apply(from:approved:)"))
        let arguments = JSON.object([
            "preview": .string(previewID(from: request)),
            "actions": .array(approvedActions.map(JSON.string)),
        ])
        let result = await tools.run(.runApprovedCleanup, arguments: arguments,
                                     capabilities: configuration.enabledCapabilities)
        yield(.stepFinished(name: "Applying what was approved"))
        yield(.messageChunk(result))
        let applied = !result.hasPrefix("Refused") && !result.contains("It failed")
        finish(applied ? .completed : .cancelled)
    }

    public func cancel() async {
        currentTurn?.cancel()
        currentTurn = nil
        guard !streamFinished else { return }
        if turnActive {
            // The turn reports its own cancellation and finishes the stream.
            return
        }
        finish(.cancelled)
    }

    /// Explicit unload the UI can call — "free the model's memory now".
    func unloadNow() async {
        await unload()
    }

    // MARK: - the loop

    private func runTurn(userText: String) async {
        defer {
            turnActive = false
            currentTurn = nil
            scheduleIdleUnload()
        }
        startPressureWatchIfNeeded()
        appendSystemIfNeeded()
        history.append(.user(userText))
        trimHistory()

        for _ in 0..<Self.maxToolIterations {
            let output: TurnOutput
            do {
                output = try await generate(from: history)
            } catch is CancellationError {
                yield(.messageChunk("Stopped."))
                finish(.cancelled)
                return
            } catch {
                yield(.messageChunk("The on-device model could not answer: \(plain(error))"))
                finish(.failed("The on-device model could not answer: \(plain(error))"))
                return
            }
            // The parser's miss is NOT silent: whatever the model wrote after
            // the visible part streams on as the reply it is.
            let call = ToolCallParser(family: family).parse(output.fullText)
            if call == nil {
                let withheld = output.tail + output.held
                if !withheld.isEmpty { yield(.messageChunk(withheld)) }
            }
            history.append(.assistant(output.fullText))
            guard let call else { break }
            guard let tool = AgentTools.Tool(rawValue: call.name) else {
                let note = "There is no tool named \"\(call.name)\". The available tools are: \(AgentTools.Tool.allCases.map(\.rawValue).joined(separator: ", "))."
                history.append(.tool(note))
                yield(.messageChunk(note))
                continue
            }
            yield(.stepStarted(name: stepName(for: tool), detail: stepDetail(for: tool)))
            let result = await tools.run(tool, arguments: decode(call.argumentsJSON),
                                         capabilities: configuration.enabledCapabilities)
            history.append(.tool(summarized(result)))
            yield(.stepFinished(name: stepName(for: tool)))
            if tool == .proposeCleanup, let request = previewRequest(from: result) {
                pendingRequests[request.id] = request
                yield(.permissionRequest(request))
                break
            }
            if tool == .runApprovedCleanup { break }
        }
        trimHistory()
        finish(.completed)
    }

    /// The permission round-trip after a preview: the proposed action is the
    /// stable string the session validates answers against, and the preview
    /// id travels inside it, so an apply can only ever name the run the
    /// person reviewed.
    private func previewRequest(from result: String) -> AgentPermissionRequest? {
        guard let range = result.range(of: #"job id: ([0-9A-Fa-f\-]{36})"#, options: .regularExpression) else {
            return nil
        }
        let id = String(result[range].dropFirst("job id: ".count))
        return AgentPermissionRequest(title: "Apply this cleanup?",
                                      proposedActions: ["cleanup:\(id)"])
    }

    private func previewID(from request: AgentPermissionRequest) -> String {
        request.proposedActions.first.map { action in
            action.hasPrefix("cleanup:") ? String(action.dropFirst("cleanup:".count)) : action
        } ?? ""
    }

    // MARK: - generation

    private struct TurnOutput: Sendable {
        /// What already streamed to the person while it generated: everything
        /// before a possible tool-call marker.
        let streamed: String
        /// The trailing fragment held back because it could still grow into
        /// the marker (empty once a marker was found).
        let tail: String
        /// From the first tool-call marker on: withheld from the chat, shown
        /// only when no call can be parsed (raw passthrough).
        let held: String
        var fullText: String { streamed + tail + held }
    }

    private func generate(from messages: [Chat.Message]) async throws -> TurnOutput {
        if container == nil {
            container = try await load()
        }
        guard let loaded = container else {
            throw EngineRefusal("The model could not be loaded. Choose a downloaded model in Settings › Agents › On-Device Models.")
        }
        let maxTokens = Self.maxNewTokens
        let startMarker = family.startMarker
        return try await loaded.perform { context -> TurnOutput in
            let userInput = UserInput(chat: messages, processing: UserInput.Processing())
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.3)
            let cache = context.model.newCache(parameters: parameters)
            let iterator = try TokenIterator(
                input: input, model: context.model, cache: cache, parameters: parameters)
            var detokenizer = NaiveStreamingDetokenizer(tokenizer: context.tokenizer)
            var gate = StreamGate(startMarker: startMarker)
            for token in iterator {
                if Task.isCancelled { break }
                if let eos = context.tokenizer.eosTokenId, token == eos { break }
                detokenizer.append(token: token)
                while let piece = detokenizer.next() {
                    let releasable = gate.feed(piece)
                    self.continuation.yield(.messageChunk(releasable))
                }
            }
            Stream.gpu.synchronize()
            let parts = gate.finish()
            return TurnOutput(streamed: parts.streamed, tail: parts.tail, held: parts.held)
        }
    }

    // MARK: - loading

    /// Loads the model from the data root's models directory, refusing with
    /// plain words when there is nothing to load or it cannot fit — a Mac
    /// that cannot keep the model and its own work in memory is told so
    /// before it swaps, not after.
    private func load() async throws -> ModelContainer {
        let directory = modelDirectory
        let fm = FileManager.default
        guard !modelID.isEmpty else {
            throw EngineRefusal("No on-device model is chosen. Choose one in Settings › Agents › On-Device Models, and it will run here, on this Mac.")
        }
        guard fm.fileExists(atPath: directory.appending(path: "config.json").path) else {
            throw EngineRefusal("The chosen model is not downloaded yet (there is no copy in \(AnalyzersPaths.displayPath(AnalyzersPaths.modelsDirectory))). Choose a downloaded model in Settings › Agents › On-Device Models.")
        }
        // Weights on disk are a fair estimate of what a quantized MLX model
        // keeps resident, so the footprint check reads the folder's bytes.
        let modelGB = Double(directoryWeight(safetensorsOnly: true, at: directory)) / 1_073_741_824.0
        let assessment = MachineAssessment.assess()
        guard assessment.canFit(modelMemoryGB: modelGB) else {
            throw EngineRefusal("This model needs about \(Int(modelGB.rounded())) GB of memory and this Mac has \(assessment.physicalMemoryGB) GB, so it will not fit alongside the system. Choose a smaller model in Settings › Agents › On-Device Models.")
        }
        return try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(
                directory: directory, extraEOSTokens: Self.extraEOSTokens(for: family)))
    }

    private static func extraEOSTokens(for family: ToolCallFamily) -> Set<String> {
        switch family {
        case .qwen: ["<|im_end|>"]
        case .gptOss: ["<|end|>", "<|return|>", "<|call|>"]
        case .glm: ["<|user|>", "<|observation|>"]
        }
    }

    /// Byte weight of `directory`, counting only weights when asked (configs
    /// are noise in a footprint estimate).
    private func directoryWeight(safetensorsOnly: Bool, at directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if safetensorsOnly && url.pathExtension != "safetensors" { continue }
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - unloading

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            await self?.unloadIfIdle()
        }
    }

    private func unloadIfIdle() async {
        guard !turnActive else { return }
        await unload()
    }

    private func handleMemoryPressure() async {
        guard container != nil else { return }
        await unload()
        yield(.messageChunk("The Mac needed memory back, so the on-device model was unloaded. It reloads on the next question."))
    }

    /// Drops the model and its GPU caches. The next turn reloads from disk.
    private func unload() async {
        guard container != nil else { return }
        container = nil
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        GPU.clearCache()
        Stream.gpu.synchronize()
    }

    /// Starts the pressure watch once, on the first turn — an actor's init is
    /// nonisolated, so the watch cannot start there.
    private func startPressureWatchIfNeeded() {
        guard pressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak self] in
            Task { await self?.handleMemoryPressure() }
        }
        source.resume()
        pressureSource = source
    }

    // MARK: - the system prompt and context discipline

    private func appendSystemIfNeeded() {
        guard !history.contains(where: { $0.role == .system }) else { return }
        history.insert(.system(systemPrompt), at: 0)
    }

    private var systemPrompt: String {
        var lines = [
            "You are Sparehold's agent on this person's Mac. You help with memory, storage and network housekeeping.",
            "You propose; the person decides. Every scan and cleanup you run is a tracked job the person can watch and stop.",
            "Tools (only these exist):",
            tools.declarations(enabled: configuration.enabledCapabilities),
            "To use one, emit exactly this shape, then stop:",
            family.syntaxLine,
            "Capabilities switched on for this session: \(configuration.enabledCapabilities.sorted().joined(separator: ", ")). A tool outside them returns a refusal; accept it and answer in words instead of trying again.",
            "Never claim something was deleted or changed unless a tool result says it was.",
        ]
        if !configuration.prelude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("The person's own instructions:")
            lines.append(configuration.prelude)
        }
        return lines.joined(separator: "\n")
    }

    /// Keeps the conversation inside the tier's context: the oldest
    /// non-system messages go first, so the recent question and its tool
    /// results survive.
    private func trimHistory() {
        func estimate(_ messages: [Chat.Message]) -> Int {
            messages.reduce(0) { $0 + $1.content.count / Self.charactersPerToken + 4 }
        }
        while history.count > 3, estimate(history) > contextTokenLimit,
              let index = history.firstIndex(where: { $0.role != .system }) {
            history.remove(at: index)
        }
    }

    /// 16–32K tokens by memory tier — the survey's caps for local models.
    private var contextTokenLimit: Int {
        switch MachineAssessment.assess().tier {
        case 32: 32_768
        case 24: 24_576
        default: 16_384
        }
    }

    // MARK: - small helpers

    private func yield(_ event: AgentEvent) {
        guard !streamFinished else { return }
        continuation.yield(event)
    }

    private func finish(_ reason: AgentStopReason) {
        guard !streamFinished else { return }
        streamFinished = true
        continuation.yield(.done(reason))
        continuation.finish()
    }

    private func summarized(_ text: String) -> String {
        text.count <= Self.toolResultLimit ? text : String(text.prefix(Self.toolResultLimit)) + " …"
    }

    private func decode(_ argumentsJSON: String) -> JSON {
        guard let data = argumentsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSON.self, from: data) else { return .object([:]) }
        return decoded
    }

    /// What a step is called on the Working screen: plain words, with the
    /// real script or command as the detail the screen shows verbatim.
    private func stepName(for tool: AgentTools.Tool) -> String {
        switch tool {
        case .scanStorage: "Running the storage scan"
        case .scanMemory: "Running the memory scan"
        case .scanNetwork: "Taking the network snapshot"
        case .readReport: "Reading the report"
        case .proposeCleanup: "Preparing the cleanup preview"
        case .runApprovedCleanup: "Applying what was approved"
        case .suggestRule: "Writing the suggestion"
        }
    }

    private func stepDetail(for tool: AgentTools.Tool) -> String {
        switch tool {
        case .scanStorage: JobKind.storageReport.script.lastPathComponent
        case .scanMemory: JobKind.memoryReport.script.lastPathComponent
        case .scanNetwork: JobKind.networkSnapshot.script.lastPathComponent
        case .readReport: "reports/storage, reports/memory"
        case .proposeCleanup: "dry run"
        case .runApprovedCleanup: "JobStore.apply(from:approved:)"
        case .suggestRule: "suggestion only — settings are the person's"
        }
    }

    /// An error a person can read, for the screen and the model alike.
    private func plain(_ error: Error) -> String {
        if let refusal = error as? EngineRefusal { return refusal.message }
        return error.localizedDescription
    }
}

/// A refusal to load, in words for the person — never a raw MLX error.
struct EngineRefusal: Error, Sendable {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

/// Holds back text from the first tool-call marker on, so tool-call plumbing
/// never streams into the chat as prose. Text before the marker flows
/// through; a trailing fragment that could still grow into the marker waits
/// until the next piece (or the end of generation) decides what it was.
struct StreamGate {
    private let startMarker: String
    private var streamed = ""
    private var tail = ""
    private var held = ""

    init(startMarker: String) {
        self.startMarker = startMarker
    }

    /// Feed one detokenized piece; returns what may be shown now.
    mutating func feed(_ piece: String) -> String {
        if !held.isEmpty {
            held += piece
            return ""
        }
        tail += piece
        if let range = tail.range(of: startMarker) {
            held = String(tail[range.lowerBound...])
            let released = String(tail[..<range.lowerBound])
            streamed += released
            tail = ""
            return released
        }
        // A suffix that is a prefix of the marker could still become the
        // marker with the next piece — hold only that suffix back.
        let holdLimit = min(startMarker.count - 1, tail.count)
        if holdLimit > 0 {
            for hold in (1...holdLimit).reversed() {
                let candidate = tail.suffix(hold)
                if startMarker.hasPrefix(candidate) {
                    let keep = String(candidate)
                    let released = String(tail.dropLast(hold))
                    tail = keep
                    streamed += released
                    return released
                }
            }
        }
        streamed += tail
        let released = tail
        tail = ""
        return released
    }

    /// Called once generation ended: what streamed, the held-back tail (a
    /// false-positive marker prefix is raw text and flows on), and the
    /// withheld tool-call text.
    func finish() -> (streamed: String, tail: String, held: String) {
        (streamed, tail, held)
    }
}

extension ConfigStore {
    /// AGENT_MODEL read straight from config.local.sh, for call sites that
    /// need the value without owning a store (the same pattern as
    /// `currentLogViewer`). The last assignment wins, mirroring bash.
    /// Nonisolated on purpose: a file read, not store state, and the local
    /// engine's actor init needs it before any MainActor hop.
    public nonisolated static func currentAgentModelID() -> String {
        guard let text = try? String(contentsOf: AnalyzersPaths.configLocal, encoding: .utf8),
              let line = text.split(separator: "\n").last(where: { $0.contains("AGENT_MODEL=") })
        else { return "" }
        let raw = line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return cleaned
    }
}

extension ToolCallFamily {
    /// The shape the system prompt teaches the model, one line per family.
    var syntaxLine: String {
        switch self {
        case .qwen:
            #"<tool_call>{"name": "toolName", "arguments": {"key": "value"}}</tool_call>"#
        case .gptOss:
            #"<|channel|>commentary to=functions.toolName<|message|>{"key": "value"}<|end|>"#
        case .glm:
            #"<tool_call>toolName<arg_key>key</arg_key><arg_value>value</arg_value></tool_call>"#
        }
    }
}
