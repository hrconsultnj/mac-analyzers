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
