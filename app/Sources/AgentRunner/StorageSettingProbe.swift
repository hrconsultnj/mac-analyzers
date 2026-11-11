import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-storage-setting` judges itself: for every combination of the setting a
// preview was made with (Daily/Deep for Caches & Builds, Trash/Delete Permanently for Temp &
// Agents) and the setting the person's own menu holds, what the screen SHOWS, what it ASKS
// (the Apply title and confirmation) and what the ENGINE RECEIVES must agree, and all three must
// be the preview's. The engine is a stand-in script in a temporary folder with a temporary job
// index; nothing of the person's is read. Exit 1 when any case disagrees.

@MainActor func probeStorageSetting() async -> Never {
    let dir = ProbeScratch.folder("ma-probe-storage-setting")
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

                // 2b. a preview AND a logged preview of the other setting at once: the preview's wins, in what is
                //     shown and in the words (the screen asks `StorageSetting.words`)
                let both = StorageSetting.shown(kind: kind, preview: options(kind, preview), lastKnownBanner: banner(kind, !preview),
                                                chosen: options(kind, picked))
                expect(flag(kind, both) == preview, "\(label): with a logged \(name(kind, !preview)) preview too, the screen shows \(name(kind, flag(kind, both)))")
                let bothWords = StorageSetting.words(kind: kind, preview: options(kind, preview), lastKnownBanner: banner(kind, !preview),
                                                     chosen: options(kind, picked))
                expect(bothWords == CleanWords.words(kind: kind, setting: options(kind, preview)), "\(label): the words follow the logged preview, not the job's")
                let wordsFromPreview = StorageSetting.words(kind: kind, preview: options(kind, preview), lastKnownBanner: nil, chosen: options(kind, picked))
                expect(wordsFromPreview == CleanWords.words(kind: kind, setting: options(kind, preview)), "\(label): the words follow the screen's own pick, not the preview")

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
    // the shapes a person has an expected answer for
    func shape(_ values: [Double]) -> [(day: Double, freeGiB: Double)] { values.enumerated().map { (day: Double($0.offset), freeGiB: $0.element) } }
    let steadyFall = DiskRunway.outlook(shape([100, 90, 80, 70, 60, 50, 40, 30]))
    expect(steadyFall.runway != nil && (2...4).contains(steadyFall.runway?.daysToFull ?? 0), "a steady fall from 100 to 30 GB over a week counts down about 3 days, from its slope: \(steadyFall.runway?.daysToFull ?? -1) / \(steadyFall.reason)")
    let bigFall = DiskRunway.outlook(shape((0..<8).map { 200 - Double($0) * 110 / 7 }))
    expect(bigFall.runway != nil && (5...7).contains(bigFall.runway?.daysToFull ?? 0), "a steady fall from 200 to 90 GB over a week counts down about 6 days: \(bigFall.runway?.daysToFull ?? -1)")
    let oneBadEnd = DiskRunway.outlook(shape([120, 120, 120, 120, 120, 120, 120, 120, 120, 3]))
    expect(oneBadEnd.runway == nil && !oneBadEnd.reason.contains("fell") && !oneBadEnd.reason.contains("under a day"),
           "ONE bad newest reading is not believed: no alarm, no countdown: \(oneBadEnd.reason)")
    let oneBadMiddle = DiskRunway.outlook(shape([120, 120, 120, 120, 3, 120, 119, 120, 119, 120]))
    expect(oneBadMiddle.runway == nil && !oneBadMiddle.reason.contains("fell"), "one bad reading in the middle of a flat disk leaves it flat: \(oneBadMiddle.runway.map { "\($0.daysToFull)" } ?? oneBadMiddle.reason)")
    let recovered = DiskRunway.outlook(shape([120, 120, 120, 120, 120, 120, 13, 13, 110]))
    expect(recovered.runway == nil && !recovered.reason.contains("fell"), "a fall followed by recovery raises no alarm: \(recovered.runway.map { "\($0.daysToFull)" } ?? recovered.reason)")
    let recoveredAfterCleanups = DiskRunway.outlook(shape([85, 100, 115, 130, 128, 130, 13, 13, 74]))
    expect(recoveredAfterCleanups.runway == nil && !recoveredAfterCleanups.reason.contains("fell"), "13 GB then 74 GB after cleanups is no alarm: \(recoveredAfterCleanups.reason)")
    let plunge = DiskRunway.outlook(shape([120, 122, 119, 121, 120, 118, 60, 13]))
    expect(plunge.runway == nil && plunge.reason.contains("fell from about 118 GB to 13 GB"), "a plunge in two steps is told as a fall: \(plunge.reason)")
    expect(DiskRunway.forecast(Array(falling.prefix(4))) == nil, "fewer than five points give none")
    expect(DiskRunway.forecast(falling.map { (day: $0.day / 10, freeGiB: $0.freeGiB) }) == nil, "less than a week gives none")
    expect(DiskRunway.forecast(falling.map { (day: $0.day, freeGiB: 40 + $0.day) }) == nil, "a rising trend gives none")
    // a stand-in storage log: 30 days of free space rising from 33 to 124 GiB, then one run that lost
    // 110 GiB in a day. The long trend is up; the recent slope is the honest answer.
    let dir = ProbeScratch.folder("ma-probe-runway")
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
    expect(outlook.runway == nil && outlook.reason.contains("fell from about 118 GB to 13 GB"),
           "a disk that lost 105 GiB in a day (118, 60, 13) is told as a fall, not predicted: \"\(outlook.reason)\"")
    // the same long trend with no recent drop is still no forecast
    var calm = ""
    for day in 0..<31 { calm += "storage-auto-clean.sh | mode=daily | APPLY | \(formatter.string(from: start.addingTimeInterval(Double(day) * 86_400)))\nFree space now: \(33 + day * 3)Gi avail (50% used)\n" }
    try? calm.write(to: log, atomically: true, encoding: .utf8)
    expect(DiskRunway.outlook(DiskRunway.series(in: log)).runway == nil, "a steadily rising disk still has no forecast")
    // the shape of this Mac's real log: a week rising to 130 GiB, then 13, 13. The week's fitted line still
    // points up; the sentence must say what happened, and no forecast is given.
    var real = ""
    let rising: [Int] = [85, 88, 91, 94, 97, 100, 103, 106, 109, 112, 115, 118, 121, 124, 127, 130, 128, 130]
    for (i, free) in rising.enumerated() {
        real += "storage-auto-clean.sh | mode=daily | APPLY | \(formatter.string(from: start.addingTimeInterval((14.0 + Double(i) * 0.4) * 86_400)))\nFree space now: \(free)Gi avail (50% used)\n"
    }
    real += "storage-auto-clean.sh | mode=daily | APPLY | \(formatter.string(from: start.addingTimeInterval(21.2 * 86_400)))\nFree space now: 13Gi avail (98% used)\n"
    real += "storage-auto-clean.sh | mode=daily | APPLY | \(formatter.string(from: start.addingTimeInterval(21.5 * 86_400)))\nFree space now: 13Gi avail (98% used)\n"
    try? real.write(to: log, atomically: true, encoding: .utf8)
    let shapedSeries = DiskRunway.series(in: log)
    let shaped = DiskRunway.outlook(shapedSeries)
    expect(shaped.runway == nil, "after a fall from about 130 to 13 there is no countdown")
    expect(shaped.reason.contains("fell from about") && shaped.reason.contains("13 GB"), "the reason says what happened: \"\(shaped.reason)\"")
    expect(!shaped.reason.contains("steady or rising"), "a fall of 117 GB is never called steady or rising")
    // a small dip is not a fall
    let dip = DiskRunway.outlook((0..<10).map { (day: Double($0), freeGiB: 100 + Double($0)) } + [(day: 10, freeGiB: 95), (day: 10.5, freeGiB: 96)])
    expect(!dip.reason.contains("fell from"), "a dip of a few GB is not told as a fall")
    // Temp's notes are sentences, not the engine's shorthand
    let rules = TempReview.rulesSentence("temp idle 24h+ · agent scratch idle 3d+ · npx tools idle 14d+ · never anything open, live, someone else's, or a mounted image you have not approved")
    expect(rules?.hasPrefix("Temporary files are cleared after a day without use, coding agents' scratch folders after three days and npx tools after two weeks.") == true, "the rules sentence reads \"\(rules ?? "nil")\"")
    expect(rules.map { !$0.contains("24h") && !$0.contains("3d") } == true, "no engine shorthand is left in the rules sentence")
    let clean = TempReview.selfCleanSentence("macOS also deletes /tmp files untouched for 3+ days each night (tmp_cleaner) — it skips mounted images and anything still being used")
    expect(clean?.contains("three days") == true && clean?.contains("tmp_cleaner") == false, "the self-clean sentence reads \"\(clean ?? "nil")\"")
    expect(TempReview.rulesSentence("something else") == nil, "a rules line in an unknown shape is dropped, not shown raw")
    print("\(cases) checks, \(failures == 0 ? "all hold" : "\(failures) FAILED")")
    exit(failures == 0 ? 0 : 1)
}
