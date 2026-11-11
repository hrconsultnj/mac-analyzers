import Foundation
import os
@_spi(TestSupport) import AnalyzersKit

// Headless proofs of the rules the job store itself owns, so no screen has to
// remember them: `--probe-review-rules` (what `apply(from:)` refuses) and
// `--probe-quit` (what each quit choice does). Test scripts and temporary
// job indexes only; nothing here can reach the real engine.

private func scratch(_ name: String) -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func script(_ dir: URL, _ name: String, _ body: String) -> URL {
    let url = dir.appending(path: name)
    try? "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    chmod(url.path, 0o755)
    return url
}

@MainActor private func wait(for job: Job) async {
    while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(30)) }
}

@MainActor private func refusal(_ job: Job) -> String {
    if case .failed(let failure) = job.state { return "refused: \(failure.message)" }
    return "ACCEPTED (\(job.intent.rawValue), state \(job.state))"
}

@MainActor func probeReviewRules() async -> Never {
    let dir = scratch("ma-probe-review")
    defer { try? FileManager.default.removeItem(at: dir) }
    // a clock the probe moves, so "16 minutes later" needs no waiting
    var offset: TimeInterval = 0
    let store = JobStore(ledger: JobLedger(url: dir.appending(path: "jobs.jsonl")),
                         clock: { Date().addingTimeInterval(offset) })
    store.scriptOverride = script(dir, "ok.sh", "echo \"memory auto-clean  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')\"")
    let matched = OSAllocatedUnfairLock(initialState: true)
    // the fixture stands in for "the log held this job's own block"
    store.outcomeOverride = { _, _ in
        JobOutcome(parsed: .none, run: nil, match: matched.withLock { $0 } ? .exact : .newestFallback("fixture: block not found"))
    }

    print("review window: \(Int(JobStore.reviewWindow / 60)) minutes")
    print("direct apply, no preview:            " + refusal(store.enqueue(JobRequest(kind: .memoryClean, intent: .apply), trigger: .user)))
    print("cleaner run by hand, not a schedule: " + refusal(store.enqueue(JobRequest(kind: .memoryClean, intent: .run), trigger: .user)))

    let approved = ApprovedSet(approvable: ["1"], deselected: [])
    func idle() async { while store.running != nil || !store.queued.isEmpty { try? await Task.sleep(for: .milliseconds(30)) } }

    let preview = store.enqueue(JobRequest(kind: .memoryClean, intent: .preview), trigger: .user)
    await wait(for: preview)
    print("preview just finished, apply now:    " + refusal(store.apply(from: preview, approved: approved)))
    await idle()

    offset = JobStore.reviewWindow + 60
    print("same preview, 16 minutes later:      " + refusal(store.apply(from: preview, approved: approved)))
    offset = 0

    let second = store.enqueue(JobRequest(kind: .memoryClean, intent: .preview), trigger: .user)
    await wait(for: second)
    store.dismiss(second)
    print("a discarded preview, apply now:      " + refusal(store.apply(from: second, approved: approved)))

    matched.withLock { $0 = false }
    let third = store.enqueue(JobRequest(kind: .memoryClean, intent: .preview), trigger: .user)
    await wait(for: third)
    print("a preview whose own block wasn't found: " + refusal(store.apply(from: third, approved: approved)))

    // a scheduled replay reads the installed plist itself; what the caller passes is ignored
    let echo = script(dir, "echo.sh", "echo \"memory auto-clean  |  APPLY  |  $(date '+%Y-%m-%d %H:%M:%S')\"; echo \"args: $*\"")
    store.scriptOverride = echo
    let label = "com.mac-analyzers.storage-autoclean.daily"
    store.scheduleReader = { _ in (script: JobKind.storageClean.script.path, arguments: ["--mode", "daily", "--dry-run"]) }
    let replay = store.enqueue(
        JobRequest(kind: .storageClean, intent: .run,
                   options: JobOptions(scheduleArguments: ["--apply", "--docker-images", "--prune-snapshots"])),
        trigger: .schedule(label))
    await wait(for: replay)
    print("Run now, caller passed --apply by hand, plist says --mode daily --dry-run:")
    print("  " + (replay.lines.first { $0.hasPrefix("args:") } ?? "(no output) " + refusal(replay)))
    await idle()

    store.scheduleReader = { _ in (script: "/somewhere/else/storage-auto-clean.sh", arguments: ["--apply"]) }
    print("plist names another copy of the script: " + refusal(store.enqueue(JobRequest(kind: .storageClean, intent: .run), trigger: .schedule(label))))
    store.scheduleReader = { _ in nil }
    print("agent not installed:                    " + refusal(store.enqueue(JobRequest(kind: .storageClean, intent: .run), trigger: .schedule(label))))
    exit(0)
}

@MainActor func probeQuit() async -> Never {
    let dir = scratch("ma-probe-quit")
    defer { try? FileManager.default.removeItem(at: dir) }
    let tree = script(dir, "tree.sh", """
    echo "memory auto-clean  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "### Working"
    sleep 7231 &
    ( sleep 7232 ; echo never ) &
    sleep 7233
    """)

    func alive() -> [String] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", "sleep 723[123]"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        try? pgrep.run()
        pgrep.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").map(String.init)
    }
    func lines(_ url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    // A. Stop and Quit
    let ledgerA = dir.appending(path: "a.jsonl")
    let storeA = JobStore(ledger: JobLedger(url: ledgerA))
    storeA.scriptOverride = tree
    let runningA = storeA.enqueue(JobRequest(kind: .memoryClean, intent: .preview), trigger: .user)
    let waitingA = storeA.enqueue(JobRequest(kind: .storageClean, intent: .preview), trigger: .user)
    try? await Task.sleep(for: .seconds(2))
    print("A. Stop and Quit — before: hasWork=\(storeA.hasWork), processes alive: \(alive().count)")
    let started = Date()
    let ended = await storeA.stopEverything()
    let took = String(format: "%.1fs", Date().timeIntervalSince(started))
    print("   stopEverything returned \(ended) after \(took); running job: \(runningA.state), waiting job: \(waitingA.state)")
    print("   processes alive afterwards: \(alive().count)")
    print("   index lines on disk at that moment: \(lines(ledgerA).count)")
    for line in lines(ledgerA) {
        let flags = ["\"cancelled\":true", "\"kind\":\"memoryClean\"", "\"kind\":\"storageClean\""].filter(line.contains)
        print("     \(flags.joined(separator: " "))")
    }

    // B. Quit and Let It Finish
    let ledgerB = dir.appending(path: "b.jsonl")
    let storeB = JobStore(ledger: JobLedger(url: ledgerB))
    storeB.scriptOverride = tree
    let runningB = storeB.enqueue(JobRequest(kind: .memoryClean, intent: .preview), trigger: .user)
    let waitingB = storeB.enqueue(JobRequest(kind: .storageClean, intent: .preview), trigger: .user)
    try? await Task.sleep(for: .seconds(2))
    await storeB.recordRunningForQuit()
    print("B. Quit and Let It Finish — after recordRunningForQuit: running job: \(runningB.state), waiting job: \(waitingB.state)")
    print("   processes still alive (the job goes on): \(alive().count)")
    for line in lines(ledgerB) {
        let flags = ["\"cancelled\":true", "\"cancelled\":false", "\"kind\":\"memoryClean\"", "\"kind\":\"storageClean\"",
                     "\"trigger\":\"user\"", "\"runHeader\":\"memory auto-clean"].filter(line.contains)
        print("     \(flags.joined(separator: " "))\(line.contains("\"exit\"") ? " (has exit)" : " (no exit)")")
    }
    // tidy up what B left running on purpose
    runningB.cancel()
    try? await Task.sleep(for: .seconds(1))
    let leftover = Process()
    leftover.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    leftover.arguments = ["-f", "sleep 723[123]"]
    try? leftover.run()
    leftover.waitUntilExit()
    exit(0)
}

// `--probe-review-session` proves the review table's rules without a screen:
// a review is tied to its preview, ticks survive leaving and returning, an expired
// review is refused, and a row that cannot be chosen never reaches the approved list.
@MainActor func probeReviewSession() -> Never {
    final class Tally { var failed = 0 }
    let tally = Tally()
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { tally.failed += 1 }
    }
    let first = UUID(), second = UUID()
    let items: [ReviewSelection.Item] = [
        .init(id: "/a"), .init(id: "/b"), .init(id: "/c"),
        .init(id: "/kept", choosable: false),
    ]
    var session = ReviewSelection(previewID: first, items: items)

    // 1. a session against a newer preview is refused
    check("same preview: ready",
          session.gate(previewID: first, finishedAt: Date()) == .ready)
    check("newer preview: refused",
          session.gate(previewID: second, finishedAt: Date()) == .differentPreview,
          session.gate(previewID: second, finishedAt: Date()).sentence ?? "")
    check("no preview: no apply", session.gate(previewID: nil, finishedAt: nil) == .noPreview)

    // 2. expired: disabled, with the sentence
    let late = Date().addingTimeInterval(JobStore.reviewWindow + 60)
    check("expired: refused", session.gate(previewID: first, finishedAt: Date(), now: late) == .expired,
          session.gate(previewID: first, finishedAt: Date(), now: late).sentence ?? "")

    // 3. a row that cannot be chosen never reaches the approved list
    session.selectAll()
    check("kept row: not ticked after Select All", !session.isTicked("/kept"))
    session.setTicked("/kept", true)
    check("kept row: cannot be ticked by hand", !session.isTicked("/kept"))
    check("kept row: not in the approved list", !session.approved.approved.contains("/kept"),
          "approved: \(session.approved.approved)")
    check("all choosable ticked: list is sent (narrowed by the kept row), without it",
          session.approved.approved == ["/a", "/b", "/c"] && session.approved.isNarrowed)
    let plain = ReviewSelection(previewID: first, items: [.init(id: "/a"), .init(id: "/b")])
    check("no kept rows and nothing unticked: not narrowed", !plain.approved.isNarrowed)
    session.selectNone()
    check("Select None: nothing approved", session.approved.approved.isEmpty)

    // 4. ticks survive leaving and returning (the store outlives the screen)
    let store = ReviewTickStore()
    session.selectAll()
    session.setTicked("/b", false)
    store.save(session.deselected, for: first)
    let returned = ReviewSelection(previewID: first, items: items, deselected: store.deselected(for: first))
    check("ticks survive leaving and returning",
          !returned.isTicked("/b") && returned.isTicked("/a") && returned.approved.approved == ["/a", "/c"],
          "approved: \(returned.approved.approved)")
    check("another preview starts fully ticked", ReviewTickStore().deselected(for: second) == nil)
    store.drop(first)
    check("dropped once applied or discarded", store.deselected(for: first) == nil)
    store.save(["/x"], for: second)
    store.keepOnly([first])
    check("an expired preview's ticks are forgotten", store.deselected(for: second) == nil)

    // folded empty rows start unticked, and Select All returns to that
    var folded = ReviewSelection(previewID: first, items: [.init(id: "/big"), .init(id: "/empty")], startsUnticked: ["/empty"])
    check("rows folded out of sight start unticked", folded.isTicked("/big") && !folded.isTicked("/empty"))
    check("Select All with only the fold unticked: nothing to do, button disabled", folded.isAllSelected)
    folded.selectAll()
    check("Select All changes nothing there; the folded row reaches the kernel as deselected",
          !folded.isTicked("/empty") && folded.approved.approved == ["/big"] && folded.approved.isNarrowed)
    folded.setTicked("/empty", true)
    folded.selectAll()
    check("a hand-ticked folded row survives Select All", folded.isTicked("/empty") && folded.isAllSelected)
    folded.setTicked("/big", false)
    check("an unticked visible row enables Select All, which ticks it and leaves the fold alone",
          !folded.isAllSelected && { folded.selectAll(); return folded.isTicked("/big") && folded.isTicked("/empty") }())

    // a caller's own approval rule can only remove: kept rows, unticked rows and unknown keys never go
    var rule = ReviewSelection(previewID: first, items: [.init(id: "/a"), .init(id: "/b"), .init(id: "/kept", choosable: false),
                                                           .init(id: "/empty")], startsUnticked: ["/empty"])
    rule.setTicked("/b", false)
    let greedy = ApprovedSet(approvable: ["/a", "/b", "/kept", "/empty", "/stranger"], deselected: [])
    check("an approval rule cannot add kept, unticked, fold or unknown keys", rule.narrowed(greedy).approved == ["/a"],
          "sent: \(rule.narrowed(greedy).approved)")
    check("an approval rule that removes a row is honoured",
          rule.narrowed(ApprovedSet(approvable: ["/a"], deselected: ["/a"])).approved.isEmpty)
    check("an unrestricted approval means the ticks", rule.narrowed(.everything).approved == ["/a"])

    // 6. a new review with the SAME number of rows shows its own rows, not the old tree
    final class Owner {}
    let memo = IdentityMemo<Owner, Int, [String]>()
    let reviewOne = Owner(), reviewTwo = Owner()
    let treeOne = memo.value(for: reviewOne, key: 0) { ["/a", "/b"] }
    let again = memo.value(for: reviewOne, key: 0) { ["never built"] }
    check("same review and sort: tree reused (not rebuilt on a tick)", treeOne == again && memo.builds == 1)
    let treeTwo = memo.value(for: reviewTwo, key: 0) { ["/c", "/d"] }
    check("same row count, different review: the tree shows the new rows", treeTwo == ["/c", "/d"],
          "tree: \(treeTwo)")
    _ = memo.value(for: reviewTwo, key: 1) { ["/d", "/c"] }
    check("sort changed: tree rebuilt", memo.builds == 3)

    // 7. after Apply, a new preview enables Apply again; an old message never shows against it
    var applied = PerPreview<String>()
    applied.set("applied: refused (old)", for: first)
    check("apply recorded against its own preview", applied.value(for: first) != nil)
    check("new preview: Apply is enabled again and the old message is gone", applied.value(for: second) == nil)
    check("no preview: nothing recorded", applied.value(for: nil) == nil)
    let broken = tally.failed
    if broken == 0 { print("all review-session rules hold") } else { print("\(broken) rule(s) broken") }
    exit(broken == 0 ? 0 : 1)
}
