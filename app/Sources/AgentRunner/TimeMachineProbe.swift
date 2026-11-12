import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-tm` judges itself. It runs the REAL `tm-reclaim.sh` in a throwaway HOME with stand-in
// `tmutil`, `sudo` and `df` that only log what they were asked (nothing real is read or changed, no snapshot,
// backup or permission is ever touched), and checks that what it printed is what the Time Machine screen reads:
// the banner is a banner, the block is found whole in its own log, the snapshots become rows by day with the
// system's own kept apart, an apply is read as Deleted with the free space before and after, a refused deletion
// is read as needing permission. It also proves what the app SENDS (preview and apply arguments, with and without
// the backup) against a stand-in engine, and what the permission prompt would run, as text that is only printed.
// Exit 1 when anything differs.

@MainActor func probeTimeMachine() async -> Never {
    let fm = FileManager.default
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    var script: URL?
    for _ in 0..<8 {
        let candidate = dir.appending(path: "storage-analyzer/tm-reclaim.sh")
        if fm.fileExists(atPath: candidate.path) { script = candidate; break }
        dir = dir.deletingLastPathComponent()
    }
    guard let script else { print("FAIL: tm-reclaim.sh was not found in any folder above \(CommandLine.arguments[0]), so this probe did not run"); exit(1) }

    let root = ProbeScratch.folder("ma-probe-tm")
    let home = root.appending(path: "home"), stubs = root.appending(path: "stubs")
    for folder in [home, stubs] { try? fm.createDirectory(at: folder, withIntermediateDirectories: true) }
    var failures = 0, cases = 0
    func expect(_ ok: Bool, _ what: @autoclosure () -> String) { cases += 1; if !ok { failures += 1; print("FAIL  \(what())") } }

    // stand-ins: tmutil lists three snapshots (two TM, one macOS) and logs; sudo logs and obeys a deny file; df counts
    let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyy-MM-dd-HHmmss"
    // the probe's clock is noon of the current day, so "an hour ago" is today at any hour the probe runs
    // (read off the wall clock it was yesterday between midnight and one, and the day names were wrong)
    let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    let today = stamp.string(from: now.addingTimeInterval(-3_600)), earlier = stamp.string(from: now.addingTimeInterval(-3 * 86_400))
    let calls = root.appending(path: "calls.log"), deny = root.appending(path: "deny"), counter = root.appending(path: "df-count")
    func write(_ name: String, _ body: String) { let url = stubs.appending(path: name); try? body.write(to: url, atomically: true, encoding: .utf8); chmod(url.path, 0o755) }
    write("tmutil", "#!/bin/bash\necho \"tmutil $*\" >> \"\(calls.path)\"\nif [[ \"$1\" == listlocalsnapshots ]]; then\n  echo com.apple.TimeMachine.\(today).local\n  echo com.apple.TimeMachine.\(earlier).local\n  echo com.apple.os.update-AB12\nfi\n")
    write("sudo", "#!/bin/bash\necho \"sudo $*\" >> \"\(calls.path)\"\n[[ -f \"\(deny.path)\" ]] && exit 1\nexit 0\n")
    write("df", "#!/bin/bash\nn=$(cat \"\(counter.path)\" 2>/dev/null || echo 0); echo $((n + 1)) > \"\(counter.path)\"\nif [[ $n -eq 0 ]]; then a=51Gi; else a=60Gi; fi\nprintf 'Filesystem Size Used Avail Capacity Mounted on\\n/dev/x 460Gi 400Gi %s 89%% /System/Volumes/Data\\n' $a\n")

    func run(_ arguments: [String]) -> (lines: [String], status: Int32) {
        try? fm.removeItem(at: counter)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.environment = ["HOME": home.path, "PATH": "\(stubs.path):/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return ([], -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return (text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, process.terminationStatus)
    }
    func calledLines() -> [String] { ((try? String(contentsOf: calls, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
    let log = home.appending(path: "mac-analyzers/reports/storage/tm-reclaim.log")

    // the preview
    let preview = run(["--dry-run"])
    let banner = preview.lines.compactMap { RunMatcher.banner(in: $0) }.first
    expect(banner?.hasPrefix("tm-reclaim | DRY RUN | backup=on | ") == true, "the preview has a banner: \(banner ?? "none")")
    let review = TimeMachineReview.build(lines: preview.lines, now: now)
    expect(review.deletable == 2, "two local snapshots can be deleted, got \(review.deletable)")
    expect(review.rows.rows.filter { !$0.isChoosable }.map(\.group) == [Names.Temp.managedByMacOS], "macOS's own snapshot is kept apart: \(review.rows.rows.map { "\($0.group ?? "-"):\($0.title)" })")
    expect(Set(review.rows.rows.filter(\.isChoosable).compactMap(\.group)).contains("Today") && review.rows.rows.filter(\.isChoosable).count == 2, "snapshots are grouped by day, today first: \(review.rows.rows.compactMap(\.group))")
    expect(review.freeBefore == "51Gi", "free space before is read: \(review.freeBefore ?? "nil")")
    if let banner, case .block(let block) = WholeRun.find(banner: banner, in: log) {
        expect(TimeMachineReview.build(lines: block.lines, now: now).deletable == 2, "the block found in the log by its banner gives the same snapshots")
    } else { expect(false, "the block was not found in tm-reclaim.log by its banner") }
    expect(calledLines().allSatisfy { $0.hasPrefix("tmutil listlocalsnapshots") } && calledLines().count == 1, "a preview only listed the snapshots: \(calledLines())")

    // an apply that worked
    try? fm.removeItem(at: calls)
    let applied = run(["--apply", "--no-backup"])
    let after = TimeMachineReview.build(lines: applied.lines, results: true, now: now)
    expect(applied.status == 0 && after.freeAfter == "60Gi" && after.rows.facts.first == "free space 51Gi → 60Gi", "an apply is read with the free space before and after: \(after.rows.facts)")
    expect(after.rows.rows.filter(\.isChoosable).allSatisfy { $0.valueText == "Deleted" }, "each snapshot reads Deleted")
    expect(calledLines().filter { $0.hasPrefix("sudo") } == ["sudo -n /usr/bin/tmutil thinlocalsnapshots / 999999999999 4"], "exactly one whitelisted thin call: \(calledLines())")
    expect(!calledLines().contains { $0.contains("startbackup") }, "--no-backup starts no backup")

    // an apply that was refused
    try? fm.removeItem(at: calls); try? "x".write(to: deny, atomically: true, encoding: .utf8)
    let refused = run(["--apply"])
    let denied = TimeMachineReview.build(lines: refused.lines, results: true, now: now)
    expect(refused.status == 3 && denied.needsPermission, "a refused deletion exits 3 and is read as needing permission (exit \(refused.status))")
    expect(denied.rows.rows.filter(\.isChoosable).allSatisfy { $0.valueText == "Couldn't Delete" }, "each snapshot reads Couldn't Delete")
    expect(!calledLines().contains { $0.contains("startbackup") }, "no backup starts when thinning was refused")
    try? fm.removeItem(at: deny)

    // what the app sends, through the real job store, to a stand-in engine
    let engine = root.appending(path: "engine.sh")
    try? "#!/bin/bash\nmode=APPLY; [[ \"$*\" == *--dry-run* ]] && mode=\"DRY RUN\"\necho \"tm-reclaim | $mode | stand-in | $(date '+%Y-%m-%d %H:%M:%S')\"\necho \"args: $*\"\n".write(to: engine, atomically: true, encoding: .utf8)
    chmod(engine.path, 0o755)
    let store = JobStore(ledger: JobLedger(url: root.appending(path: "jobs.jsonl")))
    store.scriptOverride = engine
    store.outcomeOverride = { _, _ in JobOutcome(parsed: .none, run: nil, match: .exact) }
    func wait(_ job: Job) async { while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(20)) } }
    for backup in [true, false] {
        let job = store.enqueue(JobRequest(kind: .tmReclaim, intent: .preview, options: JobOptions(startBackup: backup)), trigger: .user)
        await wait(job)
        expect(job.lines.contains("args: --dry-run"), "a preview sends --dry-run: \(job.lines)")
        let apply = store.apply(from: job, approved: .everything)
        await wait(apply)
        let sent = apply.lines.first { $0.hasPrefix("args:") } ?? ""
        expect(sent == (backup ? "args: --apply" : "args: --apply --no-backup"), "an apply \(backup ? "with" : "without") the backup sends \"\(sent)\"")
    }
    expect(StorageSetting.options(kind: .tmReclaim, banner: "tm-reclaim | DRY RUN | backup=off | 2026-11-11 10:00:00").startBackup == false
           && StorageSetting.options(kind: .tmReclaim, banner: "tm-reclaim | APPLY | backup=on | 2026-11-11 10:00:00").startBackup, "the backup setting is read from the banner")

    await probeTimeMachinePermission(root: root, repo: script.deletingLastPathComponent().deletingLastPathComponent(), expect: { expect($0, $1) })

    print("\(cases) checks, \(failures == 0 ? "the script's output, what is sent and what the prompt runs all agree" : "\(failures) FAILED")")
    exit(failures == 0 ? 0 : 1)
}
