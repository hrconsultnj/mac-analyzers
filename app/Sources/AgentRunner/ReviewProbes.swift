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
        JobOutcome(parsed: .none, run: nil, match: matched.withLock { $0 } ? .exact : .newestFallback(RunMatcher.Reason.tooLarge))
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
    print("a preview whose results were too large to review: " + refusal(store.apply(from: third, approved: approved)))

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

    // an apply sends exactly the reviewed list, even with nothing unticked
    matched.withLock { $0 = true }
    let listing = script(dir, "list.sh", """
    mode=APPLY; [[ "$*" == *--dry-run* ]] && mode="DRY RUN"
    echo "stand-in  |  $mode  |  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "args: $*"
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--only-paths" || "$1" == "--only-pids" ]]; then echo "list: $(tr '\\n' ',' < "$2")"; fi
      shift
    done
    """)
    store.scriptOverride = listing
    print("\nthe reviewed list, nothing unticked (a new item after the review is not in it):")
    for (kind, keys) in [(JobKind.storageClean, ["/p/a/.next", "/p/b/dist"]), (.janitor, ["/d/one.pdf", "/d/two.pdf"]),
                         (.tempClean, ["/tmp/x", "/tmp/y"]), (.memoryClean, ["4101", "4102"]), (.reclaim, ["4101"])] {
        let review = store.enqueue(JobRequest(kind: kind, intent: .preview), trigger: .user)
        await wait(for: review)
        let apply = store.apply(from: review, approved: ApprovedSet(approvable: keys, deselected: []))
        await wait(for: apply)
        let list = (apply.lines.first { $0.hasPrefix("list:") } ?? "list: (none sent)").dropFirst(6)
        let appeared = kind == .memoryClean || kind == .reclaim ? "4999" : "/new/after-the-review"
        print("  \(kind.rawValue): sent \(list)  — \(appeared) in it: \(list.contains(appeared) ? "YES" : "no")")
        await idle()
    }
    print("\nevery kind that can apply, and the list flag it is given:")
    for kind in JobKind.allCases where kind.isCleaner {
        print("  \(kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \(kind.approvalFlag ?? "none: its script takes no list")")
    }
    print("\na key with a line break is never written to the list:")
    let crafted = "x\n/Users/me/Downloads/other.zip"      // two lines, the second a real item
    let keys = ["/Users/me/Downloads/a.pdf", crafted, "/Users/me/Downloads/other.zip"]
    let unticked: Set<String> = ["/Users/me/Downloads/other.zip"]
    let set = ApprovedSet(approvable: keys, deselected: unticked)
    if let file = try? set.writeFile(for: .janitor) {
        let written = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: file)
        let lines = written.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        print("  \(keys.count) keys offered, other.zip unticked → list holds \(lines): other.zip approved: \(lines.contains("/Users/me/Downloads/other.zip") ? "YES (BAD)" : "no")")
        print("  \(ApprovedSet.unlistableReason)")
    }

    print("\na preview is applied once:")
    store.scriptOverride = listing
    let once = store.enqueue(JobRequest(kind: .janitor, intent: .preview), trigger: .user)
    await wait(for: once)
    let firstApply = store.apply(from: once, approved: ApprovedSet(approvable: ["/d/one.pdf"], deselected: []))
    print("  first apply:                              " + refusal(firstApply))
    print("  same preview again, first still running:  " + refusal(store.apply(from: once, approved: ApprovedSet(approvable: ["/d/one.pdf"], deselected: []))))
    await wait(for: firstApply)
    await idle()
    print("  same preview again, first finished:       " + refusal(store.apply(from: once, approved: ApprovedSet(approvable: ["/d/one.pdf"], deselected: []))))
    store.scriptOverride = script(dir, "fails2.sh", "[[ \"$*\" == *--dry-run* ]] && { echo \"stand-in  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')\"; exit 0; }; echo \"stand-in  |  APPLY  |  $(date '+%Y-%m-%d %H:%M:%S')\"; exit 5")
    let failedPreview = store.enqueue(JobRequest(kind: .storageClean, intent: .preview), trigger: .user)
    await wait(for: failedPreview)
    let failing = store.apply(from: failedPreview, approved: ApprovedSet(approvable: ["/p/x"], deselected: []))
    await wait(for: failing)
    await idle()
    print("  first apply FAILED (\(failing.state.isFinished ? "exit 5" : "?")), same preview again: " + refusal(store.apply(from: failedPreview, approved: ApprovedSet(approvable: ["/p/x"], deselected: []))))
    print("an apply for a kind that takes a list, with no list:")
    let bare = store.enqueue(JobRequest(kind: .storageClean, intent: .preview), trigger: .user)
    await wait(for: bare)
    print("  " + refusal(store.apply(from: bare, approved: .everything)))
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

    // a row the apply acts on without a tick ("will quit"): counted, named, never in the sent set
    let quit = ReviewAlsoActs(singular: "app", plural: "apps", verb: "will quit", confirmVerb: "Quit")
    let acting = ReviewSelection(previewID: first, items: [.init(id: "1"), .init(id: "Opera", acts: true),
                                                             .init(id: "Docker", acts: true), .init(id: "kept", choosable: false)])
    check("acting rows are never in the approved list",
          !acting.approved.approved.contains("Opera") && !acting.approved.approved.contains("Docker") && acting.approved.isNarrowed,
          "approved: \(acting.approved.approved)")
    check("acting rows are not kept rows", acting.actingIDs == ["Opera", "Docker"] && !acting.isChoosable("Opera"))
    check("the bar names them: 1 selected · 2 apps will quit · 1 kept",
          ReviewWording.summary(selected: acting.tickedIDs.count, bytes: nil, outside: 0, tabsSpanned: 0,
                                acting: acting.actingIDs.count, alsoActs: quit, kept: 1)
              == "1 selected · 2 apps will quit · 1 kept")
    check("the confirmation names them",
          ReviewWording.confirmationTitle(verb: "Close", destination: "now", count: 1, bytes: nil, alsoActs: quit,
                                          actingNames: ["Opera", "Docker"]) == "Close 1 Item now and Quit Opera and Docker?",
          ReviewWording.confirmationTitle(verb: "Close", destination: "now", count: 1, bytes: nil, alsoActs: quit,
                                          actingNames: ["Opera", "Docker"]))
    check("across tabs: 12 selected across 3 tabs · 3.2 GB",
          ReviewWording.summary(selected: 12, bytes: 3_200_000_000, outside: 5, tabsSpanned: 3, acting: 0, alsoActs: nil, kept: 0)
              .hasPrefix("12 selected across 3 tabs · 3"))

    // freezing what is sent when the confirmation opens
    let onOffer = ReviewFrozen(sent: acting.approved, title: "Close 1 Item now?")
    var changed = acting
    changed.setTicked("1", false)
    check("the dialog's set still holds while nothing changed", onOffer.holds(for: acting.approved))
    check("the dialog closes when the live set changes under it", !onOffer.holds(for: changed.approved))

    // the clamp is `ApprovedSet.restricted` on the caller's own result (so a field a branch adds to
    // `ApprovedSet` is carried by the type, in that one method)
    let direct = ApprovedSet(approvable: ["/a", "/b", "/c"], deselected: ["/b"]).restricted(over: ["/a", "/b", "/c"], keeping: ["/a", "/c", "/zzz"])
    check("restricted keeps the keys that are in both, in review order, and flags a narrowing",
          direct.approved == ["/a", "/c"] && direct.isNarrowed && !direct.isUnrestricted, "got \(direct.approved)")
    check("restricted over a full keep set does not narrow",
          !ApprovedSet.everything.restricted(over: ["/a"], keeping: ["/a"]).isNarrowed)
    let frozenValue = ReviewFrozen(sent: rule.narrowed(greedy), title: "t")
    check("the frozen set is the clamped VALUE that Apply will send", frozenValue.sent == rule.narrowed(greedy) && frozenValue.sent.approved == ["/a"])

    // a program ended while the review is open: updated in place
    var live = ReviewSelection(previewID: first, items: [.init(id: "p1"), .init(id: "p2"), .init(id: "p3")])
    live.setTicked("p2", false)
    live.updateChoosable(["p3": false])
    check("a row that stops being choosable is unticked and never approved",
          !live.isTicked("p3") && !live.approved.approved.contains("p3"), "approved: \(live.approved.approved)")
    check("ticks on rows that stay choosable are untouched", live.isTicked("p1") && !live.isTicked("p2"))
    let countBefore = live.tickedIDs.count
    check("a row that becomes choosable starts UNTICKED, so the bar's count does not rise",
          live.updateChoosable(["p3": true]) && !live.isTicked("p3") && live.tickedIDs.count == countBefore
              && !live.approved.approved.contains("p3"), "ticked: \(live.tickedIDs)")
    check("a call that changes nothing says so (the table is not regrouped)", !live.updateChoosable(["p1": true, "p3": true]))
    live.setTicked("p3", true)
    check("the person can then tick it", live.isTicked("p3") && live.approved.approved.contains("p3"))

    // only apps to quit, nothing ticked: Apply is on, the title names them, the sent list is empty
    var onlyActing = ReviewSelection(previewID: first, items: [.init(id: "1"), .init(id: "Opera", acts: true), .init(id: "Docker", acts: true)])
    onlyActing.selectNone()
    check("nothing ticked, two acting rows: Apply has work", ReviewWording.hasWork(sent: onlyActing.tickedIDs.count, acting: 2))
    check("and the title names them", ReviewWording.confirmationTitle(verb: "Close", destination: "now", count: 0, bytes: nil,
          alsoActs: quit, actingNames: ["Opera", "Docker"]) == "Quit Opera and Docker?")
    check("and the sent list is explicitly empty", onlyActing.approved.approved.isEmpty && onlyActing.approved.isNarrowed)
    check("names read as a person says them",
          ReviewWording.nameList(["Opera"]) == "Opera" && ReviewWording.nameList(["Opera", "Docker"]) == "Opera and Docker",
          ReviewWording.nameList(["Opera", "Docker"]))
    let many = (1...12).map { "App\($0)" }
    check("above three: the first two and a count, the full list stays available",
          ReviewWording.nameList(many, noun: "apps") == "App1, App2, and 10 more apps",
          ReviewWording.nameList(many, noun: "apps"))
    check("the full list names every one", ReviewWording.fullNames(many).contains("App12"))
    check("without a noun: and 10 more", ReviewWording.nameList(many) == "App1, App2, and 10 more", ReviewWording.nameList(many))
    check("the message names all of them only when the title shortened the list",
          ReviewWording.fullActingLine(alsoActs: quit, names: ["Opera", "Docker"]) == nil
          && ReviewWording.fullActingLine(alsoActs: quit, names: ["A", "B", "C", "D"]) == "Apps to quit: A, B, C, and D.",
          ReviewWording.fullActingLine(alsoActs: quit, names: ["A", "B", "C", "D"]) ?? "nil")
    check("the title takes the names the screen supplies (what is sent)",
          ReviewWording.confirmationTitle(verb: "Close", destination: "now", count: 2, bytes: nil, alsoActs: quit,
                                          actingNames: ["Opera"]) == "Close 2 Items now and Quit Opera?")
    check("nothing ticked and nothing acting: no work", !ReviewWording.hasWork(sent: 0, acting: 0))

    // a repeated key is kept once and does not stop a debug build
    let repeated = ReviewSelection(previewID: first, items: [.init(id: "/a"), .init(id: "/a"), .init(id: "/b")])
    check("a repeated key is kept once", repeated.items.map(\.id) == ["/a", "/b"])

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

    // a key with a line break is never choosable: not through a screen's item, not through updateChoosable
    var odd = ReviewSelection(previewID: UUID(), items: [.init(id: "/ok"), .init(id: "/odd\nkey")])
    check("a key with a line break is not choosable", !odd.isChoosable("/odd\nkey") && odd.isChoosable("/ok"))
    _ = odd.updateChoosable(["/odd\nkey": true])
    odd.selectAll()
    check("and stays so when a screen calls it choosable; Select All leaves it out",
          !odd.isChoosable("/odd\nkey") && odd.approved.approved == ["/ok"] && odd.choosableCount == 1)
    let broken = tally.failed
    if broken == 0 { print("all review-session rules hold") } else { print("\(broken) rule(s) broken") }
    exit(broken == 0 ? 0 : 1)
}
