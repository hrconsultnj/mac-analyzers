import Foundation
@_spi(TestSupport) import AnalyzersKit

// Headless proofs for Activity: `--probe-activity` (what the screen groups),
// `--probe-activity-ids` (a row keeps its id while its log grows) and
// `--probe-failures` (the sentence each failed action reads). Nothing here
// touches the real job index or a real engine script.

private func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
}

private func timeText(_ date: Date?, _ format: String) -> String {
    guard let date else { return "-" }
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: date)
}

private func show(_ rows: [ActivityRow], now: Date) {
    let sections = ActivityGrouping.sections(rows)
    func line(_ row: ActivityRow) {
        let when = timeText(row.started, "HH:mm")
        let review = row.needsReview ? "  [needs review]" : ""
        print("    " + pad(when, 6) + pad(row.displayTitle, 34) + pad(row.trigger.rawValue, 10)
              + pad(row.status.rawValue, 8) + row.line + review)
    }
    if !sections.running.isEmpty {
        print("RUNNING NOW")
        sections.running.forEach(line)
    }
    for day in sections.days {
        print("\(day.title(now: now).uppercased())   (\(day.summary))")
        day.rows.forEach(line)
    }
    if !sections.neverRan.isEmpty {
        print("HASN'T RUN YET")
        for row in sections.neverRan { print("    \(row.title)") }
    }
    let ids = rows.map(\.id)
    print("rows: \(rows.count), unique ids: \(Set(ids).count)")
}

@MainActor func probeActivity(real: Bool) async -> Never {
    if real {
        let rows = ActivityJoin.rows(live: [], index: await JobLedger.standard.entries(),
                                     logs: ActivityJoin.readLogs(),
                                     titleForKind: \.rawValue, titleForLog: \.rawValue)
        show(rows, now: Date())
        exit(0)
    }

    // A fixed "now", so the fixtures below keep meaning the same thing.
    let now = Date(timeIntervalSince1970: 1_794_351_600)      // 2026-11-10 18:00 New York
    func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
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

    func block(_ id: Int, _ when: String, flags: String) -> LogRun {
        LogRun(id: id, header: "memory auto-clean  |  APPLY  |  \(when) · input: flags: \(flags)",
               lines: ["### Orphaned helpers", "[KILLED] 40 MB pid=1 x"])
    }
    let banner = job.runHeader ?? "(none)"
    let memoryRuns = [
        LogRun(id: 5, header: banner, lines: ["### Orphaned helpers", "[DRY] pid=4242 fake-helper — 120 MB"]),  // the store job's own block
        block(4, "2026-11-10 17:20:00", flags: "--apply --dev --quiet"),    // the guard's own flags
        block(3, "2026-11-10 08:30:20", flags: "--apply"),                  // the agent's flags, in its slot
        block(2, "2026-11-10 14:07:00", flags: "--apply"),                  // the agent's flags, nowhere near the slot
        LogRun(id: 1, header: "memory auto-clean  |  DRY RUN  |  2026-11-10 12:00:00 · input: interactive menu: choice 2",
               lines: ["### Orphaned helpers"]),                            // a keyboard choice: Terminal
        LogRun(id: 0, header: earlier, lines: ["### Orphaned helpers", "[DRY] pid=2 y — 40 MB"]),  // the index's run
    ]
    // a deep clean on an interval agent: no slot, but its flags are the agent's own
    let storageRuns = [
        LogRun(id: 0, header: "storage-auto-clean.sh  |  mode=deep  |  APPLY  |  2026-11-09 23:11:00 · input: flags: --mode deep --apply --docker-images --prune-snapshots",
               lines: ["### Build caches", "[DELETED] 2.0 GB  /Users/x/Projects/app/.next"]),
    ]
    let logs = [
        ActivityJoin.LogRuns(log: .memoryClean, runs: memoryRuns),
        ActivityJoin.LogRuns(log: .storageClean, runs: storageRuns),
        ActivityJoin.LogRuns(log: .persistence, runs: []),
    ]
    let slots: ActivityJoin.Slots = { log, day in
        log == .memoryClean ? [Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: day)!] : []
    }
    let agents: ActivityJoin.AgentArguments = { log in
        switch log {
        case .memoryClean: [["--apply"]]
        case .storageClean: [["--mode", "daily", "--apply"], ["--mode", "deep", "--apply", "--docker-images", "--prune-snapshots"]]
        default: []
        }
    }
    let rows = ActivityJoin.rows(live: [job.activitySnapshot], index: await ledger.entries(), logs: logs,
                                 now: now, slots: slots, agentArguments: agents,
                                 modified: { _ in nil }, hasOutput: { _ in false },
                                 titleForKind: \.rawValue, titleForLog: \.rawValue)
    print("store job banner: \(banner)")
    show(rows, now: now)
    exit(0)
}

// MARK: - ids

/// Builds Activity's rows from a COPY of a large real log, appends runs to the
/// copy and builds them again. A row id that depends on how much log precedes
/// it changes for every old row; these must not.
@MainActor func probeActivityIDs() async -> Never {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appending(path: "ma-probe-ids-\(UUID().uuidString)")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    func rows(_ log: EngineLog, at url: URL, now: Date) -> [ActivityRow] {
        ActivityJoin.rows(live: [], index: [],
                          logs: [ActivityJoin.LogRuns(log: log, runs: LogParser.runs(at: url))],
                          now: now, modified: { _ in nil }, hasOutput: { _ in true },
                          titleForKind: \.rawValue, titleForLog: \.rawValue)
    }
    func compare(_ name: String, before: [ActivityRow], after: [ActivityRow]) -> Bool {
        let afterIDs = Set(after.map(\.id))
        let afterHeaders = Set(after.compactMap(\.header))
        let kept = before.filter { $0.header.map(afterHeaders.contains) ?? true }
        let changed = kept.filter { !afterIDs.contains($0.id) }
        print("\(name): \(before.count) rows before, \(after.count) after; "
              + "\(kept.count) old rows still inside the parser's window, ids changed: \(changed.count); "
              + "\(before.count - kept.count) left the window")
        return changed.isEmpty
    }
    let now = Date()
    var allStable = true

    // a report-style log, 256 KB window far smaller than the file
    if let source = EngineLog.storageClean.url, let text = try? String(contentsOf: source, encoding: .utf8) {
        let copy = dir.appending(path: "auto-clean.log")
        try? text.write(to: copy, atomically: true, encoding: .utf8)
        let before = rows(.storageClean, at: copy, now: now)
        // the last whole run, re-stamped, appended seven times
        if let banner = text.range(of: "storage-auto-clean.sh  |", options: .backwards),
           let rule = text[..<banner.lowerBound].range(of: "====", options: .backwards) {
            let lineStart = text[..<rule.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let snippet = String(text[lineStart...])
            var grown = text
            for step in 1...7 {
                let stamp = "2027-01-01 \(String(format: "%02d", step / 60)):\(String(format: "%02d", step % 60)):00"
                grown += snippet.replacingOccurrences(
                    of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#, with: stamp, options: .regularExpression)
            }
            try? grown.write(to: copy, atomically: true, encoding: .utf8)
            print("storage log copy: \(text.count / 1024) KB, grown by \((grown.count - text.count) / 1024) KB (7 runs)")
            allStable = compare("storageClean", before: before, after: rows(.storageClean, at: copy, now: now)) && allStable
        }
    }

    // an event log grouped by day: the next day arrives
    if let source = EngineLog.guardLog.url, let text = try? String(contentsOf: source, encoding: .utf8) {
        let copy = dir.appending(path: "guard.log")
        try? text.write(to: copy, atomically: true, encoding: .utf8)
        let before = rows(.guardLog, at: copy, now: now)
        let grown = text + "2027-01-01 00:05:00 CPU-HOG sustained >=150% for 3 ticks: pid=1 /bin/x;\n"
        try? grown.write(to: copy, atomically: true, encoding: .utf8)
        allStable = compare("guardLog (a new day starts)", before: before, after: rows(.guardLog, at: copy, now: now)) && allStable
    }
    print(allStable ? "ids stable: 0 changed" : "IDS CHANGED")
    exit(allStable ? 0 : 1)
}

// MARK: - failure sentences

/// Runs each failing action through the real job store with a throwaway
/// script and prints the sentence it reads, next to the sentence the screen
/// used before jobs.
@MainActor func probeFailures() async -> Never {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appending(path: "ma-probe-failures-\(UUID().uuidString)")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    func script(_ name: String, _ body: String) -> URL {
        let url = dir.appending(path: name)
        try? "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
        return url
    }
    let ok = script("ok.sh", "echo \"temp-clean  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')\"")
    let fail = script("fail.sh", "exit ${FAIL_CODE:-3}")
    let store = JobStore(ledger: JobLedger(url: dir.appending(path: "jobs.jsonl")))

    func finish(_ job: Job) async -> String {
        while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(30)) }
        if case .failed(let failure) = job.state { return failure.message }
        return "(did not fail: \(job.state))"
    }
    func now(_ kind: JobKind, _ intent: JobIntent, _ options: JobOptions = JobOptions(), code: Int32 = 3) async -> String {
        setenv("FAIL_CODE", String(code), 1)
        store.scriptOverride = fail
        return await finish(store.enqueue(JobRequest(kind: kind, intent: intent, options: options), trigger: .user))
    }
    func fences() async -> String {
        store.scriptOverride = ok
        let preview = store.enqueue(JobRequest(kind: .spotlight, intent: .preview), trigger: .user)
        _ = await finish(preview)
        setenv("FAIL_CODE", "3", 1)
        store.scriptOverride = fail
        return await finish(store.apply(from: preview, approved: .everything))
    }

    let image = "/private/tmp/x/Disk Image 7"
    let rows: [(String, String, String)] = [
        ("Spotlight audit (exit 3)", ExitExplanation.explain(exitCode: 3, verb: "run the audit"),
         await now(.spotlight, .preview)),
        ("Spotlight fences (exit 3)", ExitExplanation.explain(exitCode: 3, verb: "apply fences"), await fences()),
        ("Temp audit (exit 3)", ExitExplanation.explain(exitCode: 3, verb: "run the audit"),
         await now(.tempClean, .preview)),
        ("Eject (exit 3)", ExitExplanation.explain(exitCode: 3, verb: "eject Disk Image 7"),
         await now(.eject, .run, JobOptions(mountPoint: image))),
        ("Report (exit 3)", ExitExplanation.explain(exitCode: 3, verb: "write the report"),
         await now(.memoryReport, .run)),
        ("Setup, scripts missing (exit 127)",
         "Could not find memory-analyzer/memory-manage-agents.sh — the app's copy of the analyzer scripts is incomplete.",
         await now(.installAgents, .run, code: 127)),
    ]
    for (name, before, after) in rows {
        print("\(name)\n  before: \(before)\n  now:    \(after)\n")
    }
    exit(0)
}


/// `--probe-activity-log <file>`: Activity's one-line summary of each of the newest
/// runs in a storage log file, read the way the real log is. For a log written by a
/// newer or older version of the script than the one running.
func probeActivityLog(_ path: String) -> Never {
    let runs = LogParser.runs(at: URL(fileURLWithPath: path))
    print("\(runs.count) runs read from \(URL(fileURLWithPath: path).lastPathComponent)")
    for run in runs.prefix(4) {
        let summary = ActivitySummary.of(run, in: .storageClean)
        let prune = run.lines.filter { $0.contains("prune:") }.count
        print("  \(String(run.header.prefix(60))) | prune rows: \(prune) | \"\(summary.text)\" findings \(summary.findings)")
    }
    exit(0)
}
