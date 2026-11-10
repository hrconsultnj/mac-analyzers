import Darwin
import Foundation

/// How a run of one engine script ended.
public struct EngineResult: Sendable {
    public let exitCode: Int32
    /// The script died from a signal (a cancel, or a crash) rather than exiting.
    public let killedBySignal: Bool
    /// `cancel()` was called before the process was seen to end.
    public let wasCancelled: Bool
    /// Everything it printed (stdout and stderr, interleaved), when the caller
    /// asked for it; the tail if it printed more than `outputLimit`.
    public let output: String
    /// True when the process was actually started.
    public let launched: Bool
}

/// One engine script run: spawn, stream, exit.
///
/// The engine stays bash and stays the authority. This only starts it the way
/// launchd does, reads what it prints while it runs, and can stop it for real.
///
/// - Output is read with `readabilityHandler` while the child runs. (The old
///   runner read only after exit, so a child printing more than the ~64 KB pipe
///   buffer blocked forever.) stdout and stderr share one pipe, so their
///   interleaving is exactly what the script produced.
/// - Lines are delivered in order, in batches, at most ten times a second.
/// - The environment is the scheduled runs': `PATH` as in the launchd plists,
///   `HOME`, working directory = the script's folder, interpreter `/bin/bash`.
public final class EngineProcess: @unchecked Sendable {
    // @unchecked Sendable: every mutable field below is read and written only
    // while holding `lock`; the immutable fields are set once in `init`.

    /// The PATH the launchd plists give the scheduled runs.
    public static func enginePath(home: String) -> String {
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(home)/.local/bin"
    }

    /// The app's environment with the scheduled runs' `PATH` and `HOME`. The
    /// rest is inherited on purpose (`TMPDIR`, `USER`, `LANG`) — launchd adds
    /// the same ones to the scheduled runs.
    public static func engineEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        home: String = AnalyzersPaths.home.path
    ) -> [String: String] {
        var env = base
        env["PATH"] = enginePath(home: home)
        env["HOME"] = home
        return env
    }

    public let script: URL
    public let args: [String]
    private let collectOutput: Bool
    private let outputLimit: Int
    private let flushInterval: TimeInterval
    private let interpreter: URL
    private let queue = DispatchQueue(label: "engine-process.flush")

    private let lock = NSLock()
    private var process: Process?
    private var cancelRequested = false
    private var finished = false
    private var partial = Data()
    private var pending: [String] = []
    private var collected = Data()
    private var lastFlush: Date = .distantPast
    private var flushScheduled = false
    private var continuation: AsyncStream<[String]>.Continuation?

    /// `flushInterval` of 0.1 is the "at most ten times a second" rule.
    public init(script: URL, args: [String], interpreter: URL = URL(fileURLWithPath: "/bin/bash"),
                collectOutput: Bool = false, outputLimit: Int = 8_000_000,
                flushInterval: TimeInterval = 0.1) {
        self.script = script
        self.args = args
        self.interpreter = interpreter
        self.collectOutput = collectOutput
        self.outputLimit = outputLimit
        self.flushInterval = flushInterval
    }

    /// Runs the script to the end. `onLines` receives each batch in order and
    /// is awaited, so it never runs concurrently with itself.
    public func run(onLines: @escaping @Sendable ([String]) async -> Void = { _ in }) async -> EngineResult {
        // A missing engine used to arrive as exit code -1 with the reason
        // buried in the output string, which every caller then rendered as
        // "the script stopped with code -1". Say it plainly instead.
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            let text = "engine missing: \(script.lastPathComponent) was not found at \(script.path)"
            await onLines([text])
            return EngineResult(exitCode: 127, killedBySignal: false, wasCancelled: false,
                                output: text, launched: false)
        }

        let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
        lock.withLock { self.continuation = continuation }
        let consumer = Task { for await batch in stream { await onLines(batch) } }

        let pipe = Pipe()
        let reading = pipe.fileHandleForReading
        let child = Process()
        child.executableURL = interpreter
        child.arguments = [script.path] + args
        child.currentDirectoryURL = script.deletingLastPathComponent()
        child.environment = Self.engineEnvironment()
        child.standardOutput = pipe
        child.standardError = pipe
        child.standardInput = FileHandle.nullDevice
        reading.readabilityHandler = { [weak self] handle in self?.readAvailable(from: handle) }

        var launchError: String?
        let ended: (status: Int32, signalled: Bool)? = await withCheckedContinuation { resume in
            child.terminationHandler = { finished in
                resume.resume(returning: (finished.terminationStatus, finished.terminationReason == .uncaughtSignal))
            }
            let shouldLaunch = lock.withLock { () -> Bool in
                if cancelRequested { return false }
                process = child
                return true
            }
            guard shouldLaunch else { resume.resume(returning: nil); return }
            do {
                try child.run()
            } catch {
                launchError = "could not launch \(script.lastPathComponent): \(error.localizedDescription)"
                lock.withLock { process = nil }
                resume.resume(returning: nil)
            }
        }
        // The parent's copy of the write end must close, or EOF never arrives.
        try? pipe.fileHandleForWriting.close()

        finish(reading: reading)
        continuation.finish()
        await consumer.value

        let cancelled = lock.withLock { cancelRequested }
        let output = lock.withLock { String(decoding: collected, as: UTF8.self) }
        guard let ended else {
            return EngineResult(exitCode: launchError == nil ? 143 : -1, killedBySignal: false,
                                wasCancelled: cancelled, output: launchError ?? output, launched: false)
        }
        return EngineResult(exitCode: ended.status, killedBySignal: ended.signalled,
                            wasCancelled: cancelled, output: output, launched: true)
    }

    /// Stops the script and everything it started: leaf-first SIGTERM of the
    /// whole descendant tree, SIGKILL for what is left after five seconds.
    /// Safe to call at any time, from any thread, any number of times.
    public func cancel() {
        let pid: Int32? = lock.withLock {
            cancelRequested = true
            guard let process, process.isRunning else { return nil }
            return process.processIdentifier
        }
        guard let pid else { return }
        Task.detached(priority: .userInitiated) { await ProcessTree.terminate(root: pid) }
    }

    // MARK: - reading

    private func readAvailable(from handle: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        // After the final drain the descriptor is non-blocking and
        // `availableData` would raise, so a late callback must not read.
        guard !finished else { return }
        let data = handle.availableData
        if data.isEmpty {          // EOF: stop, or the handler spins
            handle.readabilityHandler = nil
            return
        }
        feed(data)
    }

    /// Called once the process has ended: reads whatever is still in the pipe
    /// without blocking (a surviving grandchild may hold the pipe open, so
    /// reading to EOF could wait forever), then flushes everything.
    private func finish(reading handle: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        handle.readabilityHandler = nil
        finished = true
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 { feed(Data(buffer[0..<count])) }
            else if count < 0 && errno == EINTR { continue }
            else { break }
        }
        if !partial.isEmpty { emit(partial[...]); partial.removeAll() }
        flushLocked()
    }

    /// Lock held. Splits into lines and schedules the next batch.
    private func feed(_ data: Data) {
        if collectOutput {
            collected.append(data)
            if collected.count > outputLimit + outputLimit / 2 {
                collected.removeFirst(collected.count - outputLimit)
            }
        }
        partial.append(data)
        var lineStart = partial.startIndex
        var index = lineStart
        while index < partial.endIndex {
            if partial[index] == 10 {
                emit(partial[lineStart..<index])
                lineStart = index + 1
            }
            index += 1
        }
        partial = Data(partial[lineStart...])
        if partial.count > 65_536 {      // a "line" that never ends
            emit(partial[...])
            partial.removeAll()
        }
        scheduleFlush()
    }

    private func emit(_ bytes: Data.SubSequence) {
        var slice = bytes
        if slice.last == 13 { slice = slice.dropLast() }
        pending.append(String(decoding: slice, as: UTF8.self))
    }

    private func scheduleFlush() {
        guard !flushScheduled, !pending.isEmpty else { return }
        flushScheduled = true
        let wait = max(0, flushInterval - Date().timeIntervalSince(lastFlush))
        queue.asyncAfter(deadline: .now() + wait) { [self] in
            lock.withLock {
                flushScheduled = false
                flushLocked()
            }
        }
    }

    private func flushLocked() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending = []
        lastFlush = Date()
        continuation?.yield(batch)
    }
}
