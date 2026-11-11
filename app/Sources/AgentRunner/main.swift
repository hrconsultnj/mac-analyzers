// agent-runner — the compiled launchd entry point for the bash engine.
//
// Exists because Background Task Management refuses to attribute a background
// item whose ProgramArguments[0] is a bare shell script (no Team ID to hold
// responsible — DTS-confirmed; see tasks-plans/research/login-items-btm-*).
// The installed plists point HERE (inside the app bundle, sharing the app's
// signing identity), and this binary immediately BECOMES the engine script
// via execv — the engine stays bash, only the doorway is compiled.
import Foundation
@_spi(TestSupport) import AnalyzersKit

let args = Array(CommandLine.arguments.dropFirst())

// `agent-runner --probe-setup` prints the same checklist the Setup screen
// shows, as plain text. Support can ask for its output, and it is the only
// way to see the verdicts on a Mac you cannot click through.
if args.first == "--probe-setup" {
    let engine = EngineStatus.probe()
    let report = SetupAudit.probe(
        notifications: SetupCheck(id: "notifications", title: "Alerts",
                                  why: "", verdict: .unset,
                                  detail: "not queryable outside the app"),
        loginItem: SetupCheck(id: "login", title: "Opens at login",
                              why: "", verdict: .unset,
                              detail: "not queryable outside the app"))
    print("engine: \(engine.summary)  root: \(AnalyzersPaths.suiteRoot.path)")
    print("bundled: \(AnalyzersPaths.usingBundledEngine)")
    for check in report.checks {
        let mark: String
        switch check.verdict {
        case .ready: mark = "OK   "
        case .blocking: mark = "BLOCK"
        case .degraded: mark = "WARN "
        case .unset: mark = "-    "
        }
        print("\(mark) \(check.title): \(check.detail)")
    }
    print("\(report.ready)/\(report.total) ready · usable: \(report.isUsable)")
    exit(report.isUsable ? 0 : 1)
}

// `agent-runner --probe-memory [--all]` prints the Monitor pane's full
// memory census as text: where physical memory is, then every process group
// with its total. Same numbers the pane shows; `--all` lists every group
// instead of the 40 largest.
if args.first == "--probe-memory" {
    let census = MemoryCensus.take()
    if let memory = census.breakdown {
        print("in use \(MemorySize.text(memory.usedBytes)) of \(MemorySize.text(memory.totalBytes))"
              + "  =  app \(MemorySize.text(memory.appBytes))"
              + " + wired \(MemorySize.text(memory.wiredBytes))"
              + " + compressed \(MemorySize.text(memory.compressedBytes))"
              + " (holding \(MemorySize.text(memory.compressedOriginalBytes)))")
        print("cached files \(MemorySize.text(memory.cachedBytes))"
              + " · free \(MemorySize.text(memory.freeBytes))")
    }
    print("\(census.processCount) processes in \(census.groups.count) groups hold"
          + " \(MemorySize.text(census.totalBytes))"
          + " · \(census.unmeasuredCount) could not be measured")
    for category in CensusGroup.Category.allCases {
        let groups = census.groups(in: category)
        print("\n\(category.title): \(MemorySize.text(census.totalBytes(in: category)))"
              + " · \(census.processCount(in: category)) processes · \(groups.count) groups")
        let shown = args.contains("--all") ? groups : Array(groups.prefix(40))
        for group in shown {
            let size = MemorySize.text(group.totalBytes)
            let pad = String(repeating: " ", count: max(0, 9 - size.count))
            print("  \(pad)\(size)  ×\(group.members.count)  \(group.name)"
                  + ((group.partsSummary ?? group.role).map { "  — \($0)" } ?? ""))
        }
        if shown.count < groups.count {
            let rest = groups.dropFirst(shown.count)
            print("  … \(rest.count) smaller groups hold"
                  + " \(MemorySize.text(rest.reduce(0) { $0 + $1.totalBytes }))")
        }
    }
    exit(0)
}

// `agent-runner --probe-job <kind> [--apply] [--cancel-after <seconds>]` runs one
// tracked job through the same kernel the app uses and prints its output as it
// arrives, then how it ended and which log block it was matched to. Cleaners
// run as a preview (a dry run). `--apply` builds the apply from that preview,
// exactly as the app does, and is ALWAYS refused against the real engine: it
// exists only to exercise the apply path with a test script. Nothing in this
// binary can apply a real clean that no person has reviewed.
//
// Undocumented test hooks (support never needs these):
//   --probe-job-script <path>   run this script instead of the engine's, with
//                               the arguments the kind built
//   --probe-ledger <path>       write the job index there instead of the real one
//   --queue-also <kind>         enqueue a second job right behind the first, print the
//                               lane states, cancel the second while it is still queued
//   --direct-apply              try to enqueue an apply without a preview (must be refused)
//   --probe-ledger-stress <path> <count>
//                               append <count> synthetic entries to a ledger and
//                               print its line count (the cap is 500)
if args.first == "--probe-ledger-stress" {
    guard args.count >= 3, let count = Int(args[2]) else {
        FileHandle.standardError.write(Data("usage: agent-runner --probe-ledger-stress <path> <count>\n".utf8))
        exit(2)
    }
    let url = URL(fileURLWithPath: args[1])
    let ledger = JobLedger(url: url)
    for index in 0..<count {
        await ledger.append(JobLedgerEntry(
            id: UUID(), kind: .storageClean, intent: .preview, trigger: "user",
            start: Date(), end: Date(), exit: 0, cancelled: false, runHeader: "synthetic \(index)"))
    }
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    print("appended \(count); ledger now has \(lines.count) lines (cap \(JobLedger.lineCap))"
          + " · first: \(lines.first.map(String.init) ?? "-")")
    exit(lines.count <= JobLedger.lineCap ? 0 : 1)
}

// `agent-runner --probe-activity [--real]` prints Activity's sections as text;
// `--probe-activity-ids` proves a row's id survives its log growing;
// `--probe-failures` prints the failure sentences. See ActivityProbes.swift.
if args.first == "--probe-activity" {
    await probeActivity(real: args.contains("--real"))
}
if args.first == "--probe-activity-ids" {
    await probeActivityIDs()
}
if args.first == "--probe-failures" {
    await probeFailures()
}
// `--probe-review-rules` shows what `apply(from:)` itself refuses; `--probe-quit`
// shows what each choice of the quit dialog does to the store. See ReviewProbes.swift.
if args.first == "--probe-review-rules" {
    await probeReviewRules()
}
if args.first == "--probe-quit" {
    await probeQuit()
}

// `agent-runner --probe-pid-recycle` proves a stop refuses a recycled pid.
// It starts a `sleep`, remembers its birth, then asks the signal path to act
// twice: once with a birth one second off, which is what a recycled pid looks
// like (it must refuse), and once with the birth it really has (it must signal).
if args.first == "--probe-pid-recycle" {
    let sleeper = Process()
    sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleeper.arguments = ["60"]
    try? sleeper.run()
    let pid = sleeper.processIdentifier
    guard let birth = ProcessTree.Birth.of(pid) else { print("could not read birth"); exit(1) }
    print("sleep pid \(pid) born \(birth.seconds).\(String(format: "%06d", birth.microseconds))")
    let stale = ProcessTree.Birth(seconds: birth.seconds - 1, microseconds: birth.microseconds)
    let refused = !ProcessTree.signalIfSame(pid: pid, expected: stale, signal: SIGKILL)
    usleep(300_000)
    let survived = sleeper.isRunning
    print("SIGKILL with a birth one second off (pid recycled): \(refused ? "REFUSED" : "SENT") — still running: \(survived)")
    let sent = ProcessTree.signalIfSame(pid: pid, expected: birth, signal: SIGKILL)
    sleeper.waitUntilExit()
    print("SIGKILL with the real birth: \(sent ? "SENT" : "REFUSED") — still running: \(sleeper.isRunning)")
    exit(refused && survived && sent && !sleeper.isRunning ? 0 : 1)
}

if args.first == "--probe-job" {
    await probeJob(args)
}

@MainActor func probeJob(_ args: [String]) async -> Never {
    func value(after flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }
    func fail(_ text: String) -> Never {
        FileHandle.standardError.write(Data((text + "\n").utf8))
        exit(2)
    }
    guard args.count >= 2, let kind = JobKind(rawValue: args[1]) else {
        fail("usage: agent-runner --probe-job <kind> [--apply] [--cancel-after <seconds>]\n"
             + "kinds: \(JobKind.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    let script = value(after: "--probe-job-script").map { URL(fileURLWithPath: $0) }
    let store = JobStore(ledger: value(after: "--probe-ledger").map { JobLedger(url: URL(fileURLWithPath: $0)) }
                         ?? .standard)
    store.scriptOverride = script
    // an apply built from a test script's preview: the script's banner is never in the
    // real log, so mark the fixture as matched (the kernel refuses a preview whose own
    // block was not found)
    if script != nil, args.contains("--apply") {
        store.outcomeOverride = { _, _ in JobOutcome(parsed: .none, run: nil, match: .exact) }
    }

    if args.contains("--direct-apply") {
        let job = store.enqueue(JobRequest(kind: kind, intent: .apply), trigger: .user)
        if case .failed(let failure) = job.state {
            print("refused: \(failure.message)")
            exit(0)
        }
        print("NOT refused: a direct apply was accepted")
        exit(1)
    }
    let wantsApply = args.contains("--apply")
    if wantsApply && script == nil {
        fail("refusing --apply against the real engine: the probe previews only. Apply from the app, "
             + "or pass --probe-job-script with a test script.")
    }
    let cancelAfter = value(after: "--cancel-after").flatMap(Double.init)
    let started = Date()

    func describe(_ state: Job.State) -> String {
        switch state {
        case .queued: "queued"
        case .running: "running"
        case .succeeded: "succeeded"
        case .failed(let failure): "failed — \(failure.message)"
        case .cancelled(let partial): "cancelled(partial: \(partial))"
        }
    }
    func stream(_ job: Job, cancelling: Bool) async {
        var printed = 0
        func drain() {
            let fresh = job.receivedLineCount - printed
            guard fresh > 0 else { return }
            let stamp = String(format: "+%.1fs", Date().timeIntervalSince(started))
            for line in job.lines.suffix(min(fresh, job.lines.count)) { print("[\(stamp)] \(line)") }
            if fresh > job.lines.count { print("[\(stamp)] … \(fresh - job.lines.count) earlier lines scrolled out of the 2,000-line buffer") }
            printed = job.receivedLineCount
            fflush(stdout)
        }
        if cancelling, let cancelAfter {
            Task {
                try? await Task.sleep(for: .seconds(cancelAfter))
                print("[probe] cancelling after \(cancelAfter)s")
                job.cancel()
            }
        }
        while !job.state.isFinished {
            drain()
            try? await Task.sleep(for: .milliseconds(50))
        }
        drain()
    }
    func report(_ job: Job) {
        print("---")
        print("job: \(job.kind.rawValue) \(job.intent.rawValue) — \(describe(job.state))")
        print("exit: \(job.exitCode.map(String.init) ?? "-")  elapsed: \(String(format: "%.1fs", Date().timeIntervalSince(started)))")
        print("received lines: \(job.receivedLineCount)")
        print("run header: \(job.runHeader ?? "(none printed)")")
        if case .succeeded(let outcome) = job.state {
            print("matched header: \(outcome.run?.header ?? "(no log for this kind)")")
            print("match: \(outcome.run == nil ? "none (this kind writes no run log)" : outcome.note == nil ? "exact" : "FALLBACK to newest — \(outcome.note ?? "")")")
            if let log = kind.log, let newest = LogParser.runs(for: log).first {
                print("newest in log: \(newest.header)")
                print("same run: \(newest.header == outcome.run?.header ? "yes" : "NO")")
            }
        }
        fflush(stdout)
    }

    let first = store.enqueue(JobRequest(kind: kind, intent: kind.isCleaner ? .preview : .run), trigger: .user)
    if let other = value(after: "--queue-also").flatMap(JobKind.init(rawValue:)) {
        let second = store.enqueue(JobRequest(kind: other, intent: other.isCleaner ? .preview : .run), trigger: .user)
        print("lane: \(first.kind.rawValue) \(describe(first.state)); \(second.kind.rawValue) \(describe(second.state))"
              + " · running=\(store.running?.kind.rawValue ?? "-") queued=\(store.queued.map(\.kind.rawValue))")
        second.cancel()
        print("after cancelling the queued job: \(second.kind.rawValue) \(describe(second.state)) · queued=\(store.queued.count)")
        let third = store.enqueue(JobRequest(kind: other, intent: other.isCleaner ? .preview : .run), trigger: .user)
        await stream(first, cancelling: !wantsApply)
        report(first)
        print("--- the queued job now takes the lane")
        await stream(third, cancelling: false)
        report(third)
        exit(0)
    }
    await stream(first, cancelling: !wantsApply)
    report(first)
    var last = first
    if wantsApply, case .succeeded = first.state {
        print("=== apply, built from the preview above")
        last = store.apply(from: first, approved: ApprovedSet(approvable: [], deselected: []))
        await stream(last, cancelling: true)
        report(last)
    }
    switch last.state {
    case .succeeded: exit(0)
    case .cancelled: exit(cancelAfter == nil ? 1 : 0)
    default: exit(1)
    }
}

guard let script = args.first,
      FileManager.default.isExecutableFile(atPath: script) else {
    FileHandle.standardError.write(
        Data("usage: agent-runner /absolute/path/engine-script.sh [args…]\n".utf8))
    exit(2)
}
var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
cArgs.append(nil)
execv(script, &cArgs)   // the kernel honors the script's shebang
perror("agent-runner execv")
exit(1)
