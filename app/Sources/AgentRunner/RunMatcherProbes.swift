import Foundation
import AnalyzersKit

// `agent-runner --probe-run-matcher` proves how a job's own block is found in a
// log, against stand-in logs written to a temporary folder (the real logs are
// never touched): a run of 600 KB, of 5 MB and of more than the 32 MB reach,
// two runs that print the same banner, and a log that grows while it is read.

private func item(_ index: Int) -> String { "[DRY] 4 KB  /Users/example/Downloads/file-\(index).pdf" }

private func block(banner: String, items: Int) -> String {
    ([banner, "### Downloads (untouched 60+ days)"] + (0..<items).map(item) + ["DRY RUN — would move \(items) item(s), 4 KB, to the Trash. Re-run with --apply."])
        .joined(separator: "\n") + "\n"
}

private func parsedItems(_ outcome: JobOutcome) -> Int? {
    if case .storage(let run) = outcome.parsed { return run.items.count }
    return nil
}

private func describe(_ outcome: JobOutcome) -> String {
    let match: String
    switch outcome.match {
    case .exact: match = "exact"
    case .noLog: match = "no log"
    case .newestFallback(let reason): match = "FALLBACK (\(reason))"
    }
    return "\(match), items parsed: \(parsedItems(outcome).map(String.init) ?? "-")"
}

func probeRunMatcher() -> Never {
    let dir = ProbeScratch.folder("ma-probe-run-matcher")
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String) {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name): \(detail)")
    }
    func write(_ name: String, _ text: String) -> URL {
        let url = dir.appending(path: name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    let old = block(banner: "2026-11-09 08:00 | downloads janitor | DRY RUN | downloads>60d screenshots>60d", items: 40)
    let banner = "2026-11-10 22:07 | downloads janitor | DRY RUN | downloads>60d screenshots>60d"
    let began = RunDate.date(of: banner)!.addingTimeInterval(-20)

    print("big runs (one line per file):")
    for (label, items) in [("about 600 KB", 12_000), ("about 5 MB", 100_000)] {
        let url = write("big-\(items).log", old + block(banner: banner, items: items))
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let started = ContinuousClock.now
        let outcome = RunMatcher.outcome(kind: .janitor, in: url, header: banner, startedAt: began)
        let took = started.duration(to: .now)
        var isExact = false
        if case .exact = outcome.match { isExact = true }
        check("\(label) run (\(size / 1024) KB log)", isExact && parsedItems(outcome) == items,
              "\(describe(outcome)) in \(took)")
    }
    // beyond the reach: 33 MB of one run
    let giant = dir.appending(path: "giant.log")
    FileManager.default.createFile(atPath: giant.path, contents: nil)
    if let handle = try? FileHandle(forWritingTo: giant) {
        handle.write(Data(old.utf8))
        handle.write(Data((banner + "\n### Downloads (untouched 60+ days)\n").utf8))
        let chunk = Data((0..<20_000).map { item($0) + "\n" }.joined().utf8)
        for _ in 0..<(34 * 1_048_576 / chunk.count + 1) { handle.write(chunk) }
        try? handle.close()
    }
    let giantSize = (try? FileManager.default.attributesOfItem(atPath: giant.path)[.size] as? Int) ?? 0
    let giantStarted = ContinuousClock.now
    let huge = RunMatcher.outcome(kind: .janitor, in: giant, header: banner, startedAt: began)
    let giantTook = giantStarted.duration(to: .now)
    var tooLarge = false
    if case .newestFallback(let reason) = huge.match { tooLarge = reason == RunMatcher.Reason.tooLarge }
    check("run beyond the reach (\(giantSize / 1_048_576) MB log)", tooLarge, "\(describe(huge)) in \(giantTook)")

    print("\nthe ordinary case (a small run at the end of a 3 MB log):")
    func ordinary(_ banner: String, items: Int) -> String {
        (["==================", banner, " roots=/p  cache>3d", " input: flags: --dry-run", "==================",
          "### 1. Build caches not written in >3 days"] + (0..<items).map { "[DRY] 4 KB  /p/site\($0)/.next" }
         + ["DRY RUN — identified ~4 KB reclaimable. Re-run with --apply."]).joined(separator: "\n") + "\n"
    }
    let filler = (0..<40).map { ordinary("2026-11-0\($0 % 9 + 1) 08:00:00 | storage-auto-clean.sh | mode=daily | DRY RUN | x\($0)", items: 700) }.joined()
    let ordinaryBanner = "2026-11-10 22:07:00 | storage-auto-clean.sh | mode=daily | DRY RUN | now"
    let small = write("ordinary.log", filler + ordinary(ordinaryBanner, items: 12))
    let size = (try? FileManager.default.attributesOfItem(atPath: small.path)[.size] as? Int) ?? 0
    var total = Duration.zero
    var lastRead: JobOutcome?
    for _ in 0..<20 {
        let started = ContinuousClock.now
        lastRead = RunMatcher.outcome(kind: .storageClean, in: small, header: ordinaryBanner, startedAt: RunDate.date(of: ordinaryBanner))
        total += started.duration(to: .now)
    }
    var ordinaryExact = false
    if let lastRead, case .exact = lastRead.match { ordinaryExact = true }
    check("ordinary run in a \(size / 1024) KB log", ordinaryExact, "\(lastRead.map(describe) ?? "-"), average \(total / 20) over 20 reads")

    print("\na window that starts inside a multi-byte character:")
    // The tail LogParser reads begins at (size − 256 KB). Put the second byte of "é" there.
    let window = 262_144
    var rest = "e-end-of-a-line\n"
        + ordinary("2026-11-10 20:00:00 | storage-auto-clean.sh | mode=daily | DRY RUN | a", items: 5)
        + ordinary("2026-11-10 21:00:00 | storage-auto-clean.sh | mode=daily | DRY RUN | b", items: 5)
    let padLine = "[DRY] 4 KB  /p/"
    let pad = (window - 1) - rest.utf8.count - padLine.utf8.count - 1
    rest += padLine + String(repeating: "x", count: max(0, pad)) + "\n"
    var bytes = Data("====\nolder\n".utf8)
    bytes.append(contentsOf: [0xC3, 0xA9])
    bytes.append(Data(rest.utf8))
    let edge = dir.appending(path: "edge.log")
    try? bytes.write(to: edge)
    let tail = bytes.suffix(window)
    let strict = String(data: Data(tail), encoding: .utf8)
    let runsFound = LogParser.runs(at: edge).count
    check("tail begins on a continuation byte (0x\(String(tail.first ?? 0, radix: 16)))", tail.first == 0xA9,
          "strict decode of the window: \(strict == nil ? "nil, so the old read found 0 runs" : "worked")")
    check("the log's runs are still found", runsFound >= 2, "\(runsFound) runs")

    print("\nidentical banners:")
    let same = "2026-11-10 12:00:05 | downloads janitor | DRY RUN | downloads>60d screenshots>60d"
    let twin = write("twin.log", block(banner: "2026-11-10 11:59:00 | downloads janitor | DRY RUN | x", items: 3)
                     + block(banner: same, items: 5) + block(banner: same, items: 9))
    let sameStart = RunDate.date(of: same)!
    let last = RunMatcher.outcome(kind: .janitor, in: twin, header: same, startedAt: sameStart)
    check("two runs, same second: the last block is the job's own", parsedItems(last) == 9, describe(last))
    let late = RunMatcher.outcome(kind: .janitor, in: twin, header: same, startedAt: sameStart.addingTimeInterval(30))
    var fellBack = false
    if case .newestFallback = late.match { fellBack = true }
    check("a block that began before the job is not the job's", fellBack, describe(late))
    let minute = "2026-11-10 12:00 | downloads janitor | DRY RUN | x"
    let minuteLog = write("minute.log", block(banner: minute, items: 4))
    let withinMinute = RunMatcher.outcome(kind: .janitor, in: minuteLog, header: minute,
                                          startedAt: RunDate.date(of: minute)!.addingTimeInterval(41))
    check("a minute-only banner is not earlier than a job started 41 s into that minute",
          parsedItems(withinMinute) == 4, describe(withinMinute))
    // the same banner, found by seeking from a log far larger than the window
    let twinBig = write("twin-big.log", block(banner: same, items: 5) + block(banner: same, items: 9)
                        + block(banner: "2026-11-10 12:30:00 | downloads janitor | DRY RUN | y", items: 100_000))
    let seeked = RunMatcher.outcome(kind: .janitor, in: twinBig, header: same, startedAt: sameStart)
    check("identical banners found by seeking back past a 5 MB run", parsedItems(seeked) == 9, describe(seeked))

    print("\na log that grows while it is read:")
    let growing = write("growing.log", old + block(banner: banner, items: 12_000))
    let stop = LockedFlag()
    let writer = Thread {
        guard let handle = try? FileHandle(forWritingTo: growing) else { return }
        handle.seekToEndOfFile()
        var n = 0
        // paced and bounded: under 1 MB in all, so the probe can never fill a disk
        while !stop.isSet, n < 6_000 {
            usleep(200)
            // another run starting, written in two pieces so a reader can land between them
            handle.write(Data("2026-11-10 23:\(String(format: "%02d", n % 60)):00 | downloads janitor | DRY RUN | grow\n".utf8))
            handle.write(Data("### Downloads (untouched 60+ days)\n[DRY] 4 KB  /x/".utf8))
            handle.write(Data("partial-\(n).pdf\n".utf8))
            n += 1
        }
        try? handle.close()
    }
    writer.start()
    var wrong = 0
    var seen = 0
    for _ in 0..<100 {
        switch WholeRun.find(banner: banner, in: growing, notBefore: began, firstChunk: 4096) {
        case .block(let found):
            seen += 1
            if found.lines.count != 12_000 + 2 { wrong += 1 }       // the run's own lines only
        default: wrong += 1
        }
    }
    stop.set()
    check("100 reads while a writer appends: every one found the whole run, none mis-matched",
          wrong == 0 && seen == 100, "\(seen) found, \(wrong) wrong")

    // a banner split by a chunk edge: the log is read backwards in chunks of 4096, 8192, 16384 bytes; the banner of
    // the run being looked for is placed so that each of the first three edges falls at every position in it, from
    // one byte before it to one byte after it, and it must still be found whole, with its own lines
    print("\na banner that a chunk edge splits:")
    let marked = "2026-11-10 22:07 | downloads janitor | DRY RUN | straddle"
    let markedLength = marked.utf8.count
    let older = String(repeating: "padding line of an older run\n", count: 3_000)
    var straddleFailures: [String] = []
    var straddleCases = 0
    for edge in [4096, 4096 + 8192, 4096 + 8192 + 16384] {
        for position in -1...(markedLength + 1) {
            // `edge` bytes from the end, the chunk edge falls `position` bytes into the banner
            let tailBytes = edge + position
            guard tailBytes >= markedLength + 1 else { continue }
            let body = tailBytes - markedLength - 1            // bytes after the banner line, whole lines of padding
            let bodyText = body == 0 ? "" : String(repeating: "a", count: body - 1) + "\n"
            let log = older + marked + "\n" + bodyText
            let url = write("straddle-\(edge)-\(position).log", log)
            straddleCases += 1
            switch WholeRun.find(banner: marked, in: url, firstChunk: 4096) {
            case .block(let found):
                let expectLines = body == 0 ? 0 : 1
                if found.banner != marked || found.lines.count != expectLines || found.offset != UInt64(older.utf8.count) {
                    straddleFailures.append("edge \(edge) position \(position): banner \(found.banner.prefix(20)), lines \(found.lines.count), offset \(found.offset)")
                }
            default:
                straddleFailures.append("edge \(edge) position \(position): not found")
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
    check("the banner is found whole when a chunk edge falls anywhere in it (\(straddleCases) cases, 3 edges)",
          straddleFailures.isEmpty && straddleCases > 150, straddleFailures.prefix(3).joined(separator: "; "))

    print(failures == 0 ? "\nall hold" : "\n\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}

private final class LockedFlag: @unchecked Sendable {
    // @unchecked Sendable: every access to `value` holds `lock`.
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
