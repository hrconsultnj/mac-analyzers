import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-storage-setting` judges itself: for every combination of the setting a
// preview was made with (Daily/Deep for Caches & Builds, Trash/Delete Permanently for Temp &
// Agents) and the setting the person's own menu holds, what the screen SHOWS, what it ASKS
// (the Apply title and confirmation) and what the ENGINE RECEIVES must agree, and all three must
// be the preview's. The engine is a stand-in script in a temporary folder with a temporary job
// index; nothing of the person's is read. Exit 1 when any case disagrees.

@MainActor func probeStorageSetting() async -> Never {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ma-probe-storage-setting-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let echo = dir.appending(path: "engine-stand-in.sh")
    try? "#!/bin/bash\necho \"stand-in engine  |  APPLY  |  $(date '+%Y-%m-%d %H:%M:%S')\"\necho \"args: $*\"\n"
        .write(to: echo, atomically: true, encoding: .utf8)
    chmod(echo.path, 0o755)
    let store = JobStore(ledger: JobLedger(url: dir.appending(path: "jobs.jsonl")))
    store.scriptOverride = echo
    store.outcomeOverride = { _, _ in JobOutcome(parsed: .none, run: nil, match: .exact) }
    func wait(_ job: Job) async { while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(20)) } }

    var failures = 0, cases = 0
    func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
        cases += 1
        if !ok { failures += 1; print("FAIL  \(what())") }
    }

    /// The setting as a Bool (Deep, or permanent) in the kind's own terms.
    func flag(_ kind: JobKind, _ o: JobOptions) -> Bool { kind == .storageClean ? o.deep : o.permanent }
    func options(_ kind: JobKind, _ on: Bool) -> JobOptions { kind == .storageClean ? JobOptions(deep: on) : JobOptions(permanent: on) }
    func name(_ kind: JobKind, _ on: Bool) -> String {
        kind == .storageClean ? (on ? "Deep" : "Daily") : (on ? "Delete Permanently" : "Trash")
    }
    func banner(_ kind: JobKind, _ on: Bool) -> String {
        kind == .storageClean
            ? "storage-auto-clean.sh | mode=\(on ? "deep" : "daily") | DRY RUN | 2026-11-11 08:00:00"
            : "temp-clean | DRY RUN\(on ? " (permanent)" : "") | 2026-11-11 08:00:00"
    }

    for kind in [JobKind.storageClean, .tempClean] {
        print("\(kind == .storageClean ? "Caches & Builds" : "Temp & Agents")")
        for preview in [false, true] {
            for picked in [false, true] {
                let label = "preview \(name(kind, preview)), menu \(name(kind, picked))"
                // 1. a preview is on screen (taken back from the store): the screen follows the PREVIEW
                let shown = StorageSetting.shown(kind: kind, preview: options(kind, preview), lastKnownBanner: nil,
                                                 chosen: options(kind, picked))
                expect(flag(kind, shown) == preview, "\(label): the screen shows \(name(kind, flag(kind, shown)))")
                // what it asks
                let words = CleanWords.words(kind: kind, setting: shown)!
                if kind == .tempClean {
                    expect((words.destination == "permanently") == preview && (words.applyTitle == "Delete") == preview
                           && (words.permanentWarning != nil) == preview,
                           "\(label): asks \"\(words.applyTitle)\" / \"\(words.destination)\" / second question \(words.permanentWarning != nil)")
                } else {
                    expect(words.message.contains("snapshots") == preview && words.permanentWarning != nil,
                           "\(label): the caches question does not follow the preview")
                }
                // what the engine receives, through the real apply path
                let job = store.enqueue(JobRequest(kind: kind, intent: .preview, options: options(kind, preview)), trigger: .user)
                await wait(job)
                let apply = store.apply(from: job, approved: ApprovedSet(approvable: ["/p/a", "/p/b"], deselected: []))
                await wait(apply)
                let args = apply.lines.first { $0.hasPrefix("args:") } ?? ""
                let sent = kind == .storageClean ? args.contains("--mode deep") : args.contains("--permanent")
                expect(sent == preview, "\(label): the engine received \"\(args)\"")
                if kind == .storageClean { expect(args.contains("--prune-snapshots") == preview, "\(label): snapshot thinning flag in \"\(args)\"") }
                expect(sent == flag(kind, shown) && sent == (words.destination == "permanently" && kind == .tempClean || kind == .storageClean && words.message.contains("snapshots")),
                       "\(label): shown, asked and sent disagree")

                // 2. no preview, a logged one shown read-only: the screen follows the LOG's setting
                let known = StorageSetting.shown(kind: kind, preview: nil, lastKnownBanner: banner(kind, preview), chosen: options(kind, picked))
                expect(flag(kind, known) == preview, "\(label): a logged \(name(kind, preview)) preview is shown as \(name(kind, flag(kind, known)))")

                // 3. choosing in the menu: puts the preview away exactly when the setting differs
                expect(StorageSetting.isChange(kind: kind, shown: options(kind, preview), picked: options(kind, picked)) == (preview != picked),
                       "\(label): the menu \(preview != picked ? "must" : "must not") discard")
            }
        }
        // 4. nothing on screen: the person's own pick
        for picked in [false, true] {
            let shown = StorageSetting.shown(kind: kind, preview: nil, lastKnownBanner: nil, chosen: options(kind, picked))
            expect(flag(kind, shown) == picked, "no preview, menu \(name(kind, picked)): shows \(name(kind, flag(kind, shown)))")
        }
        // 5. the banner read back is the banner written
        for on in [false, true] {
            expect(flag(kind, StorageSetting.options(kind: kind, banner: banner(kind, on))) == on, "banner of \(name(kind, on)) read wrongly")
        }
    }
    print("\n\(cases) checks, \(failures == 0 ? "all agree: what is shown, asked and sent is the preview's" : "\(failures) FAILED")")
    exit(failures == 0 ? 0 : 1)
}

// `agent-runner --probe-disk-runway` judges itself: the free-space figures `df -h` writes in any unit
// or decimal mark are read as what they say, and the forecast keeps its honest limits.
func probeDiskRunway() -> Never {
    var failures = 0, cases = 0
    func close(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.001 } ?? false }
    func expect(_ ok: Bool, _ what: String) { cases += 1; if !ok { failures += 1; print("FAIL  \(what)") } }
    let lines: [(String, Double)] = [
        ("Free space now: 13Gi avail (98% used)", 13),
        ("Free space now: 4.5Gi avail (99% used)", 4.5),
        ("Free space now: 4,5Gi avail (99% used)", 4.5),
        ("Free space now: 512Mi avail (99% used)", 0.5),
        ("Free space now: 1.2Ti avail (50% used)", 1.2 * 1024),
        ("Free space now: 2048Ki avail", 2048.0 / 1_048_576),
    ]
    for (line, gib) in lines { expect(close(DiskRunway.freeGiB(in: line), gib), "\"\(line)\" read as \(DiskRunway.freeGiB(in: line).map { "\($0)" } ?? "nothing"), expected \(gib)") }
    expect(DiskRunway.freeGiB(in: "Free space now: lots") == nil, "a line with no figure reads as nothing")
    let falling = (0..<8).map { (day: Double($0), freeGiB: 100 - Double($0) * 5) }
    expect(DiskRunway.forecast(falling) != nil, "a steady fall over a week gives a forecast")
    expect(DiskRunway.forecast(Array(falling.prefix(4))) == nil, "fewer than five points give none")
    expect(DiskRunway.forecast(falling.map { (day: $0.day / 10, freeGiB: $0.freeGiB) }) == nil, "less than a week gives none")
    expect(DiskRunway.forecast(falling.map { (day: $0.day, freeGiB: 40 + $0.day) }) == nil, "a rising trend gives none")
    // a stand-in storage log: 30 days of free space rising from 33 to 124 GiB, then one run that lost
    // 110 GiB in a day. The long trend is up; the recent slope is the honest answer.
    let dir = FileManager.default.temporaryDirectory.appending(path: "ma-probe-runway-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = dir.appending(path: "auto-clean.log")
    var text = ""
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let start = Date().addingTimeInterval(-31 * 86_400)
    func run(_ day: Double, _ free: Int) {
        text += "storage-auto-clean.sh | mode=daily | APPLY | \(formatter.string(from: start.addingTimeInterval(day * 86_400)))\nFree space now: \(free)Gi avail (50% used)\n"
    }
    for day in 0..<30 { run(Double(day), 33 + day * 3) }
    run(30.0, 118); run(30.5, 60); run(31.0, 13)
    try? text.write(to: log, atomically: true, encoding: .utf8)
    let series = DiskRunway.series(in: log)
    expect(series.count == 33, "the stand-in log gave \(series.count) figures, expected 33")
    let outlook = DiskRunway.outlook(series)
    expect(outlook.runway != nil, "a disk that lost 105 GiB in a day has a forecast, not \"\(outlook.reason)\"")
    expect((outlook.runway?.daysToFull ?? 99) < 3, "the forecast follows the recent slope (days to full: \(outlook.runway?.daysToFull ?? -1))")
    expect(outlook.reason.contains("last"), "the reason says it used the last days: \"\(outlook.reason)\"")
    // the same long trend with no recent drop is still no forecast
    var calm = ""
    for day in 0..<31 { calm += "storage-auto-clean.sh | mode=daily | APPLY | \(formatter.string(from: start.addingTimeInterval(Double(day) * 86_400)))\nFree space now: \(33 + day * 3)Gi avail (50% used)\n" }
    try? calm.write(to: log, atomically: true, encoding: .utf8)
    expect(DiskRunway.outlook(DiskRunway.series(in: log)).runway == nil, "a steadily rising disk still has no forecast")
    print("\(cases) checks, \(failures == 0 ? "all hold" : "\(failures) FAILED")")
    exit(failures == 0 ? 0 : 1)
}
