import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-storage-apply` proves the path from a tick in a review
// to the file the engine is given, for the three cleaners that take a reviewed
// list (Caches & Builds, Downloads, Temp & Agents). It builds each review's
// keys exactly as the screens do, deselects some, applies through
// `JobStore.apply(from:approved:)` against a TEST script (never the engine, with a temporary job index), and compares
// the `--only-paths` file the script received with the keys that stayed ticked.
// The real engine is never started.

@MainActor func probeStorageApply() async -> Never {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ma-probe-storage-apply-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let echo = dir.appending(path: "engine-stand-in.sh")
    try? """
    #!/bin/bash
    mode="APPLY"; [[ "$*" == *--dry-run* ]] && mode="DRY RUN"
    echo "stand-in engine  |  $mode  |  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "args: $*"
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--only-paths" ]]; then cp "$2" "$MA_PROBE_COPY"; fi
      shift
    done
    """.write(to: echo, atomically: true, encoding: .utf8)
    chmod(echo.path, 0o755)
    let copy = dir.appending(path: "received.txt")
    setenv("MA_PROBE_COPY", copy.path, 1)

    let store = JobStore(ledger: JobLedger(url: dir.appending(path: "jobs.jsonl")))
    store.scriptOverride = echo
    store.outcomeOverride = { _, _ in JobOutcome(parsed: .none, run: nil, match: .exact) }

    var failures = 0
    func wait(_ job: Job) async { while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(20)) } }
    func received() -> [String] {
        ((try? String(contentsOf: copy, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func scenario(_ title: String, kind: JobKind, keys: [String], deselect: Set<String>, expectFlag: Bool) async {
        try? FileManager.default.removeItem(at: copy)
        let preview = store.enqueue(JobRequest(kind: kind, intent: .preview), trigger: .user)
        await wait(preview)
        let approved = ApprovedSet(approvable: keys, deselected: deselect)
        let apply = store.apply(from: preview, approved: approved)
        await wait(apply)
        let args = apply.lines.first { $0.hasPrefix("args:") } ?? "(no output)"
        let flagSent = args.contains("--only-paths") || args.contains("--only-pids")
        let expected = keys.filter { !deselect.contains($0) }
        let got = received()
        let ok = flagSent == expectFlag && (!expectFlag || got == expected)
        if !ok { failures += 1 }
        let sample = args.count > 90 ? String(args.prefix(90)) + "…" : args
        print("\(ok ? "PASS" : "FAIL")  \(title): \(keys.count) offered, \(deselect.count) unticked → engine got \(flagSent ? "\(got.count) paths" : "no list")  [\(sample)]")
    }

    // keys as the screens build them: the engine's own key per row
    let downloads = StorageRunReader.run(in: AnalyzersPaths.janitorLog, header: nil)
        .map { DownloadReview.build(lines: $0.lines, info: { _ in (nil, false) }).candidates.map(\.id) } ?? []
    let temp = StorageRunReader.run(in: AnalyzersPaths.tempCleanLog, header: nil)
        .map { TempReview.build(from: TempCleanParser.parse(runHeader: $0.header, lines: $0.lines)).ready.map(\.id) } ?? []
    let caches = ["/p/site/.next", "/p/site/node_modules", "/p/api/dist", "/p/api/.turbo", "/p/web/.vite"]

    print("Caches & Builds (storageClean)")
    await scenario("nothing unticked", kind: .storageClean, keys: caches, deselect: [], expectFlag: false)
    await scenario("two unticked", kind: .storageClean, keys: caches, deselect: [caches[1], caches[3]], expectFlag: true)
    print("Downloads (janitor), \(downloads.count) real items from the latest preview")
    if downloads.count > 3 {
        await scenario("nothing unticked", kind: .janitor, keys: downloads, deselect: [], expectFlag: false)
        await scenario("three unticked", kind: .janitor, keys: downloads, deselect: Set(downloads.prefix(3)), expectFlag: true)
        await scenario("one group unticked (every 2nd item)", kind: .janitor, keys: downloads,
                       deselect: Set(downloads.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)), expectFlag: true)
    }
    print("Temp & Agents (tempClean), \(temp.count) real ready rows from the latest audit")
    if temp.count > 2 {
        await scenario("nothing unticked (the list is still sent)", kind: .tempClean, keys: temp, deselect: [], expectFlag: true)
        await scenario("two unticked", kind: .tempClean, keys: temp, deselect: Set(temp.prefix(2)), expectFlag: true)
        await scenario("everything unticked (an empty list, so nothing is touched)", kind: .tempClean, keys: temp, deselect: Set(temp), expectFlag: true)
    }
    print("")
    print(failures == 0 ? "all paths hold" : "\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}
