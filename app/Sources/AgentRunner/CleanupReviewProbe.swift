import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-cleanup-review [reclaim]` prints Memory Cleanup's
// review as the table shows it, from the real cleaner log (read only): the
// newest run that found anything, one line per row, then what the engine is
// given when some rows are unticked, and the arguments the two options add.
// Nothing is run and nothing is written.

private func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
}

func probeCleanupReview(_ args: [String]) -> Never {
    let log: EngineLog = args.contains("reclaim") ? .reclaim : .memoryClean
    let runs = LogParser.runs(for: log)
    let parsed = runs.map { ReapParser.parse(runHeader: $0.header, lines: $0.lines) }
    // the newest run with something in it — a real dry run when there is one
    let run = parsed.first { $0.dryRun && !$0.allItems.isEmpty } ?? parsed.first { !$0.allItems.isEmpty }
    guard let run else {
        print("no run in \(log.rawValue) has anything in it yet")
        exit(0)
    }
    let review = CleanupReview(run: run)
    print("run: \(run.dryRun ? "preview" : "applied") · \(review.candidates.count) rows"
          + (review.protectedNote.map { " · note: \($0.prefix(60))" } ?? ""))
    print(pad("NAME", 30) + pad("DETAIL", 22) + pad("MEMORY", 10) + pad("STATE", 22) + "WHY")
    for row in review.candidates.sorted(by: { ($0.rank, -$0.memoryBytes) < ($1.rank, -$1.memoryBytes) }).prefix(25) {
        let name = row.count > 1 ? "\(row.name) ×\(row.count)" : row.name
        print(pad(name, 30) + pad(row.detail ?? "", 22)
              + pad(row.memoryMB.map { "\($0) MB" } ?? "", 10) + pad(row.stateText, 22) + row.reason)
    }

    // the levels: a tab per kind, rows that open per app or project, nothing-rows folded
    print("\nlevels (category → group → rows):")
    var failures: [String] = []
    let tabs = review.categories()
    for tab in tabs {
        print("  \(tab.category.title)  (\(tab.count) items, \(MemorySize.text(tab.bytes)))")
        for group in tab.groups.prefix(6) {
            print("      \(group.name)  (\(group.count) items, \(MemorySize.text(group.bytes)))")
            for row in group.rows.prefix(3) { print("          \(row.name) — \(row.memoryMB.map { "\($0) MB" } ?? "") — \(row.stateText)") }
            let titles = group.rows.map(\.name)
            if Set(titles).count != titles.count { failures.append("a title repeats inside \(tab.category.title) › \(group.name)") }
        }
        if !tab.empty.isEmpty { print("      \(tab.empty.count) empty items") }
    }
    if tabs.count == 1, review.candidates.count >= 8 { failures.append("every row landed in one category") }
    print(failures.isEmpty ? "  levels: ok" : "  levels FAILED: \(failures.joined(separator: "; "))")
    let changed = review.changedSinceReview().count
    print("  tickable rows whose pid is no longer the reviewed program: \(changed)")

    print("\nselection:")
    let keys = review.approvableKeys
    print("  tickable rows: \(keys.count), asks apps to quit: \(review.appQuits.count)")
    let all = review.approvedSet(ticked: Set(keys))
    print("  everything ticked → narrowed: \(all.isNarrowed), approved \(all.approved.count) of \(keys.count), apps \(all.apps ?? [])")
    if let first = keys.first {
        let some = review.approvedSet(ticked: Set(keys).subtracting([first]))
        print("  one unticked   → approved \(some.approved.count) of \(keys.count), narrowed: \(some.isNarrowed)")
    }
    let empty = CleanupReview(run: ReapParser.parse(runHeader: "x", lines: []))
    let emptySet = empty.approvedSet(ticked: [])
    print("  nothing to tick → an explicit empty list is sent: narrowed \(emptySet.isNarrowed), approved \(emptySet.approved.count)")

    print("\narguments:")
    func show(_ kind: JobKind, _ options: JobOptions) {
        let args = (try? kind.previewArgs(options)) ?? []
        print("  \(kind.rawValue) preview \(args.joined(separator: " "))")
    }
    show(.memoryClean, JobOptions())
    show(.memoryClean, JobOptions(includeBusyOrphans: true))
    show(.reclaim, JobOptions())
    show(.reclaim, JobOptions(alsoQuit: ["Opera", "Docker"]))
    exit(0)
}

// `agent-runner --probe-cleanup-apply` proves what the engine is given when a
// review is applied, with a test script standing in for the cleaner (it
// records its own arguments and the approval file it was handed): nothing
// unticked sends no list, unticking sends exactly the ticked pids, the two
// options reach both the preview and the apply, and a review with nothing to
// tick sends an explicit empty list. No real cleaner is ever run.
@MainActor func probeCleanupApply() async -> Never {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ma-probe-cleanup-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let record = dir.appending(path: "record.txt")
    let script = dir.appending(path: "cleaner.sh")
    try? """
    #!/bin/bash
    mode="DRY RUN"; for a in "$@"; do [ "$a" = "--apply" ] && mode="APPLY"; done
    echo "memory auto-clean  |  $mode  |  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "args: $*" >> "\(record.path)"
    prev=""; for a in "$@"; do [ "$prev" = "--only-pids" ] && { echo "approved file: $(tr '\\n' ',' < "$a")" >> "\(record.path)"; }; prev="$a"; done
    """.write(to: script, atomically: true, encoding: .utf8)
    chmod(script.path, 0o755)

    // real throwaway programs, so every row has a real identity (a made-up pid would count as ended)
    func sleeper() -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["120"]
        try? p.run()
        return p
    }
    let procs = [sleeper(), sleeper(), sleeper(), sleeper()]
    defer { for p in procs where p.isRunning { p.terminate() } }
    try? await Task.sleep(for: .milliseconds(400))
    let pids = procs.map { Int($0.processIdentifier) }
    let (a, b, c, busy) = (pids[0], pids[1], pids[2], pids[3])

    let store = JobStore(ledger: JobLedger(url: dir.appending(path: "jobs.jsonl")))
    store.scriptOverride = script
    func wait(_ job: Job) async { while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(30)) } }
    func idle() async { while store.running != nil || !store.queued.isEmpty { try? await Task.sleep(for: .milliseconds(30)) } }
    func recorded() -> String {
        ((try? String(contentsOf: record, encoding: .utf8)) ?? "").split(separator: "\n").suffix(2).joined(separator: "  |  ")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
    var failed = false
    func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "ok  " : "FAIL") \(name)\n       \(detail)")
        if !ok { failed = true }
    }

    /// Previews `lines`, ticks what `ticked` says (by pid), applies through the store the way the screen does
    /// (`approvedSet(ticked:)`), and returns what the engine was given.
    func scenario(_ title: String, lines: [String], kind: JobKind = .memoryClean, options: JobOptions = JobOptions(),
                  ticked: ([Int]) -> Set<String>) async -> (given: String, approved: ApprovedSet, file: [String]?)? {
        store.outcomeOverride = { _, header in
            let banner = header ?? "memory auto-clean  |  DRY RUN"
            return JobOutcome(parsed: .reap(ReapParser.parse(runHeader: banner, lines: lines)),
                              run: LogRun(id: 0, header: banner, lines: lines), match: .exact)
        }
        let preview = store.enqueue(JobRequest(kind: kind, intent: .preview, options: options), trigger: .user)
        await wait(preview)
        await idle()
        try? FileManager.default.removeItem(at: record)
        guard case .succeeded(let outcome) = preview.state, case .reap(let run) = outcome.parsed else {
            print("\(title): preview did not finish"); return nil
        }
        let review = CleanupReview(run: run)
        let approved = review.approvedSet(ticked: ticked(review.approvableKeys.compactMap(Int.init)))
        let apply = store.apply(from: preview, approved: approved)
        await wait(apply)
        await idle()
        let text = (try? String(contentsOf: record, encoding: .utf8)) ?? ""
        let file = text.split(separator: "\n").first { $0.hasPrefix("approved file:") }
            .map { $0.dropFirst("approved file:".count).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        print("\(title)\n    ticked: \(approved.approved.count) of \(review.approvableKeys.count), apps \(approved.apps ?? [])\n    engine was given: \(recorded())")
        return (text, approved, file)
    }

    let base = ["### 3. Dev servers older than 24h",
                "[DRY]    310 MB  pid=\(a)  stale-dev (30h): next-server (v16.2.7)",
                "[DRY]    120 MB  pid=\(b)  stale-dev (26h): next-server (v16.3.1)",
                "[DRY]     64 MB  pid=\(c)  stale-dev (25h): vite"]
    print("scenarios, each applied the way the screen applies (approvedSet(ticked:), real programs):")
    let s1 = await scenario("1. everything ticked, nothing left alone", lines: base) { Set($0.map(String.init)) }
    check("a list is ALWAYS sent, even with everything ticked and nothing kept",
          s1?.file.map { Set($0) == Set([a, b, c].map(String.init)) } == true, "file \(s1?.file ?? [])")
    let s2 = await scenario("2. one row unticked", lines: base) { Set($0.map(String.init)).subtracting([String(b)]) }
    check("an unticked row is not in the list", s2?.file.map { Set($0) == Set([a, c].map(String.init)) } == true, "file \(s2?.file ?? [])")
    let s3 = await scenario("3. everything unticked", lines: base) { _ in [] }
    check("nothing ticked sends an explicit empty list", s3?.file?.isEmpty == true, "file \(s3?.file ?? ["no list"])")
    let s4 = await scenario("4. busy orphans included", lines: base, options: JobOptions(includeBusyOrphans: true)) { Set($0.map(String.init)) }
    check("the option reaches the apply and a list is sent", (s4?.given.contains("--orphans-all")) == true && s4?.file != nil,
          "file \(s4?.file ?? [])")

    // all ticked with one program left alone (a busy one the review shows as left alone)
    let withLeftAlone = base + ["[SKIP]   200 MB  pid=\(busy)  in use - no session or terminal in its project: next-server (v16.2.9)"]
    let s5 = await scenario("5. everything closable ticked, one program left alone", lines: withLeftAlone) { Set($0.map(String.init)) }
    check("the left-alone program is not in the list, and a list is sent",
          s5?.file.map { !$0.contains(String(busy)) && Set($0) == Set([a, b, c].map(String.init)) } == true, "file \(s5?.file ?? [])")

    // all ticked with a live-session row ("Kept"): an aggregate the engine counts and never closes
    let withSession = base + ["4× claude    325 MB total"]
    let s6 = await scenario("6. everything closable ticked, a live-session row kept", lines: withSession) { Set($0.map(String.init)) }
    check("a live-session row never changes the list, which is sent", s6?.file.map { Set($0) == Set([a, b, c].map(String.init)) } == true,
          "file \(s6?.file ?? [])")

    // reclaim, an app on the list that is eligible, one that was not running, and one that hosts a session
    let appLines = base + ["### 12. Quitting heavy apps",
                           "[DRY]   1413 MB  would quit: Opera",
                           "[SKIP]  Docker — not running",
                           "[SKIP]  Visual Studio Code — hosts 1 live coding session(s); quit it yourself to end them"]
    let s7 = await scenario("7. reclaim, also quit Opera, Docker and Visual Studio Code", lines: appLines, kind: .reclaim,
                            options: JobOptions(alsoQuit: ["Opera", "Docker", "Visual Studio Code"])) { Set($0.map(String.init)) }
    check("the apply quits exactly the app the review listed as 'would quit', not the names that match now",
          (s7?.given.contains("--apps-list Opera")) == true && s7?.given.contains("Docker") == false
              && s7?.given.contains("Visual Studio Code") == false && s7?.file != nil,
          recorded())
    let s8 = await scenario("8. reclaim, the only action is an app", lines: ["### 12. Quitting heavy apps", "[DRY]   1413 MB  would quit: Opera"],
                            kind: .reclaim, options: JobOptions(alsoQuit: ["Opera"])) { Set($0.map(String.init)) }
    check("with nothing to tick, an explicit empty list is sent and the listed app is still named",
          s8?.file?.isEmpty == true && s8?.given.contains("--apps-list Opera") == true, "file \(s8?.file ?? ["no list"])")

    approvalCases()
    exit(failed ? 1 : 0)
}

/// What Apply sends must be the very set the review counts: a row that is left alone, folded away as
/// using no memory, or whose program changed since the preview is never in it, whatever Select All did.
/// Real throwaway `sleep` processes stand in for the programs, so identities are real.
@MainActor private func approvalCases() {
    func sleeper() -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["120"]
        try? p.run()
        return p
    }
    let ok = sleeper(), vanishing = sleeper(), nothing = sleeper(), leftAlone = sleeper()
    defer { for p in [ok, vanishing, nothing, leftAlone] where p.isRunning { p.terminate() } }
    Thread.sleep(forTimeInterval: 0.4)
    func pid(_ p: Process) -> Int { Int(p.processIdentifier) }
    let lines = ["### 3. Dev servers older than 24h",
                 "[DRY]    310 MB  pid=\(pid(ok))  stale-dev (30h): next-server (v16.2.7)",
                 "[DRY]    120 MB  pid=\(pid(vanishing))  stale-dev (26h): next-server (v16.3.1)",
                 "[DRY]      0 MB  pid=\(pid(nothing))  stale-dev (25h): vite",
                 "[SKIP]   200 MB  pid=\(pid(leftAlone))  in use - no session or terminal in its project: next-server (v16.2.9)"]
    let review = CleanupReview(run: ReapParser.parse(runHeader: "memory auto-clean  |  DRY RUN", lines: lines))
    print("\napproval cases (what Apply sends against what the review counts):")
    for c in review.candidates { print("    row \(c.reviewKey): \(c.stateText), \(c.memoryMB ?? 0) MB, selectable \(c.isSelectable)") }

    // the program ends after the preview: its pid is no longer the program that was reviewed
    vanishing.terminate()
    vanishing.waitUntilExit()
    let changed = review.changedKeys()

    // what the table counts: one item per row that can be ticked, and Select All ticks exactly those
    let items = review.candidates.map { ReviewSelection.Item(id: $0.reviewKey, choosable: review.isTickable($0, changed: changed)) }
    var selection = ReviewSelection(previewID: UUID(), items: items, deselected: [])
    selection.selectAll()
    let counted = Set(selection.tickedIDs)
    let sent = review.approvedSet(ticked: counted)
    let sentKeys = Set(sent.approved)

    func report(_ name: String, _ ok: Bool, _ detail: String) { print("  \(ok ? "ok  " : "FAIL") \(name): \(detail)") }
    report("Select All, a left-alone row is never sent", !sentKeys.contains(String(pid(leftAlone))), "sent \(sent.approved)")
    report("Select All, a row whose program changed is never sent", !sentKeys.contains(String(pid(vanishing))),
           "changed \(changed.sorted())")
    report("Select All, a row folded away as nothing is never sent", !sentKeys.contains(String(pid(nothing))), "sent \(sent.approved)")
    report("the count and what is sent are the same programs", counted == sentKeys,
           "counted \(counted.sorted()), sent \(sentKeys.sorted())")
    report("the one program that qualifies is sent, narrowed to a list", sentKeys == [String(pid(ok))] && sent.isNarrowed,
           "narrowed \(sent.isNarrowed)")
    // nothing tickable at all: an explicit empty list, never "everything"
    let none = review.approvedSet(ticked: [])
    report("nothing ticked sends an explicit empty list", none.isNarrowed && none.approved.isEmpty, "\(none.approved)")
}
