// agent-runner — the compiled launchd entry point for the bash engine.
//
// Exists because Background Task Management refuses to attribute a background
// item whose ProgramArguments[0] is a bare shell script (no Team ID to hold
// responsible — DTS-confirmed; see tasks-plans/research/login-items-btm-*).
// The installed plists point HERE (inside the app bundle, sharing the app's
// signing identity), and this binary immediately BECOMES the engine script
// via execv — the engine stays bash, only the doorway is compiled.
import Foundation
import AnalyzersKit

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

// `agent-runner --probe-activity [--real]` prints Activity's rows as text.
// Without --real it builds a scenario out of a throwaway script and synthetic
// log blocks (nothing real is read or written): a run started through the
// store, a scheduled run and a Terminal run in the same log, a run the index
// recorded in an earlier session, a failure that never reached a log, and a
// log with no runs. With --real it joins the real logs and the real index,
// read-only, and starts nothing.
if args.first == "--probe-activity" {
    await probeActivity(real: args.contains("--real"))
}

@MainActor func probeActivity(real: Bool) async -> Never {
    func show(_ rows: [ActivityRow]) {
        let stamp = DateFormatter()
        stamp.dateFormat = "MM-dd HH:mm:ss"
        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
        }
        print(pad("TASK", 20) + pad("STARTED", 16) + pad("DUR", 7) + pad("BY", 10) + pad("STATUS", 13) + pad("SOURCE", 18) + "RESULT")
        for row in rows {
            let source: String
            switch row.source {
            case .live: source = "store"
            case .indexed: source = "index only"
            case .logged(let log, _): source = "log \(log.rawValue)"
            case .emptyLog: source = "empty log"
            }
            let duration = row.duration.map { String(format: "%.1fs", $0) } ?? "-"
            print(pad(row.title, 20) + pad(row.started.map(stamp.string(from:)) ?? "-", 16) + pad(duration, 7)
                  + pad(row.trigger.rawValue, 10) + pad(row.status.rawValue, 13) + pad(source, 18)
                  + row.result + (row.needsReview ? "  [needs review]" : ""))
        }
        let ids = rows.map(\.id)
        print("rows: \(rows.count), unique ids: \(Set(ids).count)")
    }

    if real {
        let logs = EngineLog.allCases.map { ActivityJoin.LogRuns(log: $0, runs: LogParser.runs(for: $0)) }
        let index = await JobLedger.standard.entries()
        let rows = ActivityJoin.rows(live: [], index: index, logs: logs,
                                     titleForKind: \.rawValue, titleForLog: \.rawValue)
        show(rows)
        exit(0)
    }

    // 1. a run started through the store, by a throwaway script
    let dir = FileManager.default.temporaryDirectory.appending(path: "ma-probe-activity-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appending(path: "fake-clean.sh")
    try? """
    #!/bin/bash
    echo "memory auto-clean  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "### Orphaned helpers"
    echo "[DRY] pid=4242 fake-helper — 120 MB"
    """.write(to: script, atomically: true, encoding: .utf8)
    chmod(script.path, 0o755)
    let ledger = JobLedger(url: dir.appending(path: "app-jobs.jsonl"))
    let store = JobStore(ledger: ledger)
    store.scriptOverride = script
    let job = store.enqueue(JobRequest(kind: .memoryClean, intent: .preview), trigger: .user)
    while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(50)) }
    try? await Task.sleep(for: .milliseconds(200))

    func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }
    // 2. an earlier session's run: only the index knows who started it
    let earlier = "memory auto-clean  |  DRY RUN  |  2026-11-09 10:15:00"
    await ledger.append(JobLedgerEntry(
        id: UUID(), kind: .memoryClean, intent: .preview, trigger: "user",
        start: date("2026-11-09 10:15:00"), end: date("2026-11-09 10:15:04"),
        exit: 0, cancelled: false, runHeader: earlier))
    // 3. a failure that died before logging anything
    await ledger.append(JobLedgerEntry(
        id: UUID(), kind: .tempClean, intent: .preview, trigger: "user",
        start: date("2026-11-09 11:00:00"), end: date("2026-11-09 11:00:01"),
        exit: 127, cancelled: false, runHeader: nil))

    func block(_ id: Int, _ when: String) -> LogRun {
        LogRun(id: id, header: "memory auto-clean  |  DRY RUN  |  \(when)",
               lines: ["### Orphaned helpers", "[DRY] pid=1 x — 10 MB"])
    }
    let banner = job.runHeader ?? "(none)"
    let memoryRuns = [
        LogRun(id: 4, header: banner, lines: ["### Orphaned helpers", "[DRY] pid=4242 fake-helper — 120 MB"]),  // the store job's own block
        block(3, "2026-11-10 03:30:20"),     // 20 s after the 03:30 slot
        block(2, "2026-11-10 14:07:00"),     // nowhere near a slot
        LogRun(id: 1, header: earlier, lines: ["### Orphaned helpers", "[DRY] pid=2 y — 40 MB"]),  // the index's run
    ]
    let logs = [
        ActivityJoin.LogRuns(log: .memoryClean, runs: memoryRuns),
        ActivityJoin.LogRuns(log: .persistence, runs: []),
    ]
    let slots: ActivityJoin.Slots = { log, day in
        log == .memoryClean ? [Calendar.current.date(bySettingHour: 3, minute: 30, second: 0, of: day)!] : []
    }
    let rows = ActivityJoin.rows(live: [job.activitySnapshot], index: await ledger.entries(), logs: logs,
                                 slots: slots, titleForKind: \.rawValue, titleForLog: \.rawValue)
    print("store job banner: \(banner)")
    show(rows)
    exit(0)
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
