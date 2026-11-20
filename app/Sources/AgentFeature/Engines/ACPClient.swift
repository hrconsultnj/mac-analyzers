import Foundation
import AnalyzersKit

/// How an adapter subprocess is spawned: the executable (npx), the adapter
/// package's arguments, the working directory, and an environment with the
/// engine PATH so the vendor's own binaries (`claude`, `codex`) are found.
public struct ACPSpawnSpec: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let workingDirectory: URL
    public let environment: [String: String]

    public init(executable: URL, arguments: [String], workingDirectory: URL,
                environment: [String: String] = EngineProcess.engineEnvironment()) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

/// An ACP request that failed: the wire's error object, or a local one.
public struct ACPRequestError: Error, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    init(from error: JSON) {
        let fields = error.stringFields
        self.init(code: Int(fields["code"] ?? "") ?? -32000,
                  message: fields["message"] ?? "The engine returned an error.")
    }
}

/// One ACP engine subprocess speaking newline-delimited JSON-RPC 2.0 on
/// stdio (the Agent Client Protocol's transport).
///
/// Everything about the child — the `Process`, the pipes, the line buffer —
/// lives inside this actor; only Data, JSON and Int cross in and out. The
/// child and its whole descendant tree are terminated by `stop()` and when
/// the connection goes away, so an adapter never outlives its session.
public actor ACPConnection {

    private let spec: ACPSpawnSpec
    private var process: Process?
    private var stdin: FileHandle?
    private var childPID: Int32 = 0
    private var stopped = false

    private var nextRequestID = 0
    private var pending: [Int: CheckedContinuation<JSON, Error>] = [:]
    private var readBuffer = Data()
    /// Last stderr bytes, for the sentence a dead adapter produces.
    private var stderrTail = ""

    /// Set once, before the first line is read. Notifications
    /// (`session/update`…) arrive here.
    private var onNotification: (@Sendable (String, JSON) async -> Void)?
    /// Server→client requests (`session/request_permission`,
    /// `fs/read_text_file`…) arrive here; the Result becomes the reply.
    private var onRequest: (@Sendable (String, JSON) async -> Result<JSON, ACPRequestError>)?

    init(spec: ACPSpawnSpec) {
        self.spec = spec
    }

    deinit {
        // deinit cannot await: hand the tree-kill to its own task. The pid is
        // copied out, and `ProcessTree.terminate` checks the pid's birth
        // before signalling, so a recycled pid is never touched.
        let pid = childPID
        if pid > 1 {
            Task.detached(priority: .userInitiated) {
                await ProcessTree.terminate(root: pid)
            }
        }
    }

    // MARK: - handlers

    /// Installs the session's handlers. Call before `start()`.
    func setHandlers(
        onNotification: @escaping @Sendable (String, JSON) async -> Void,
        onRequest: @escaping @Sendable (String, JSON) async -> Result<JSON, ACPRequestError>
    ) {
        self.onNotification = onNotification
        self.onRequest = onRequest
    }

    // MARK: - lifecycle

    /// Spawns the adapter. Throws in words a person can read when the
    /// executable is missing or will not start.
    func start() throws {
        guard process == nil, !stopped else { return }
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: spec.executable.path) else {
            throw ACPRequestError(code: -1, message: "\(spec.executable.lastPathComponent) was not found on this Mac.")
        }
        let child = Process()
        child.executableURL = spec.executable
        child.arguments = spec.arguments
        child.currentDirectoryURL = spec.workingDirectory
        child.environment = spec.environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = stderrPipe

        child.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { await self.childDidExit(status: status) }
        }
        do {
            try child.run()
        } catch {
            throw ACPRequestError(code: -1, message: "\(spec.executable.lastPathComponent) could not start: \(error.localizedDescription)")
        }
        process = child
        childPID = Int32(child.processIdentifier)
        stdin = stdinPipe.fileHandleForWriting
        beginReading(from: stdoutPipe.fileHandleForReading) { [weak self] data in
            Task { await self?.ingest(data) }
        }
        beginReading(from: stderrPipe.fileHandleForReading) { [weak self] data in
            Task { await self?.collectStderr(data) }
        }
    }

    var isRunning: Bool { process != nil && !stopped }

    /// Stops the adapter and its whole descendant tree. Pending requests fail
    /// with a sentence, so the session never hangs on a dead child.
    func stop() async {
        guard !stopped else { return }
        stopped = true
        process?.terminationHandler = nil
        let pid = childPID
        if pid > 1 {
            await ProcessTree.terminate(root: pid)
        }
        process = nil
        stdin = nil
        failPending(ACPRequestError(code: -1, message: "The engine was stopped."))
    }

    private func childDidExit(status: Int32) async {
        process?.terminationHandler = nil
        process = nil
        stdin = nil
        guard !stopped else { return }
        let tail = stderrTail.isEmpty
            ? ""
            : " It said: \(String(stderrTail.suffix(300)))"
        failPending(ACPRequestError(code: -1, message: "The engine exited (code \(status)).\(tail)"))
    }

    private func failPending(_ error: ACPRequestError) {
        let waiting = pending
        pending = [:]
        for continuation in waiting.values {
            continuation.resume(throwing: error)
        }
    }

    // MARK: - the wire

    /// Sends a request and awaits its response. Cancelling the awaiting task
    /// removes the pending entry, so nothing leaks.
    func request(_ method: String, _ params: JSON) async throws -> JSON {
        guard !stopped, stdin != nil else {
            throw ACPRequestError(code: -1, message: "The engine is not running.")
        }
        nextRequestID += 1
        let id = nextRequestID
        let envelope = JSON.object([
            "jsonrpc": .string("2.0"),
            "id": .int(id),
            "method": .string(method),
            "params": params,
        ])
        try write(envelope)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSON, Error>) in
                pending[id] = continuation
            }
        } onCancel: { [weak self] in
            Task { await self?.abandon(id: id) }
        }
    }

    /// Sends a notification (no id, no reply).
    func notify(_ method: String, _ params: JSON) {
        guard stdin != nil else { return }
        let envelope = JSON.object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params,
        ])
        try? write(envelope)
    }

    /// One write, inside the actor. A failed write means a dead child; the
    /// exit handler fails whatever was pending.
    private func write(_ envelope: JSON) throws {
        guard let stdin else {
            throw ACPRequestError(code: -1, message: "The engine is not running.")
        }
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        var line = data
        line.append(0x0A)
        stdin.write(line)
    }

    private func abandon(id: Int) {
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        }
    }

    // MARK: - reading

    /// The readabilityHandler pattern the engine's own runner uses: the
    /// handler reads synchronously (it runs on a dispatch queue) and hops
    /// into the actor with the bytes only.
    private func beginReading(
        from handle: FileHandle,
        into deliver: @escaping @Sendable (Data) -> Void
    ) {
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            deliver(data)
        }
    }

    private func ingest(_ data: Data) async {
        readBuffer.append(data)
        while let newline = readBuffer.firstIndex(of: 0x0A) {
            let lineData = readBuffer[..<newline]
            readBuffer.removeSubrange(..<readBuffer.index(after: newline))
            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            await handle(line)
        }
        // A "line" that never ends is dropped, not buffered forever.
        if readBuffer.count > 1_000_000 {
            readBuffer.removeAll()
        }
    }

    private func collectStderr(_ data: Data) {
        stderrTail.append(String(decoding: data, as: UTF8.self))
        if stderrTail.count > 4_000 {
            stderrTail = String(stderrTail.suffix(2_000))
        }
    }

    /// Routes one JSON-RPC line: a response to our request, a notification,
    /// or a server→client request needing an answer.
    private func handle(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(JSON.self, from: data),
              case .object(let object) = envelope
        else { return }
        let method = object["method"]?.stringValue
        let id: Int?
        if case .int(let value) = object["id"] { id = value } else { id = nil }

        if let method {
            if let id {
                await answer(requestID: id, method: method, params: object["params"] ?? .null)
            } else {
                await onNotification?(method, object["params"] ?? .null)
            }
            return
        }
        guard let id, let continuation = pending.removeValue(forKey: id) else { return }
        if let error = object["error"] {
            continuation.resume(throwing: ACPRequestError(from: error))
        } else {
            continuation.resume(returning: object["result"] ?? .null)
        }
    }

    /// Runs the session's handler for a server→client request and writes the
    /// reply (a result or a JSON-RPC error object).
    private func answer(requestID: Int, method: String, params: JSON) async {
        let result = await onRequest?(method, params) ?? .failure(
            ACPRequestError(code: -32601, message: "Method not supported: \(method)"))
        var envelope: JSON
        switch result {
        case .success(let value):
            envelope = .object([
                "jsonrpc": .string("2.0"),
                "id": .int(requestID),
                "result": value,
            ])
        case .failure(let error):
            envelope = .object([
                "jsonrpc": .string("2.0"),
                "id": .int(requestID),
                "error": .object([
                    "code": .int(error.code),
                    "message": .string(error.message),
                ]),
            ])
        }
        try? write(envelope)
    }
}
