@_spi(TestSupport) import AnalyzersKit
import Foundation

// `agent-runner --probe-memory-kinds` prints each kind of memory's screen as text, from the live kernel counters (read
// only, nothing of the person's), and judges the rules the screens rely on:
//   - every kind has a report, and its headline is the block's own figure at that moment;
//   - the history keeps 900 samples and starts again after a gap of over a minute;
//   - rates come from counter differences, never negative;
//   - the table of who holds the most compressed memory parses what `top` prints (a fixed sample, including a command
//     with spaces and the "+" and "-" change markers) and the real `top` gives rows for this Mac.
@MainActor func probeMemoryKinds() async -> Never {
    var failed = false
    func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "ok  " : "FAIL") \(name): \(detail)")
        if !ok { failed = true }
    }

    let trend = MemoryTrend()
    for _ in 0..<3 {
        await trend.sampleNow()
        try? await Task.sleep(for: .milliseconds(600))
    }
    print("\(trend.samples.count) samples taken 0.6 s apart\n")
    guard let latest = trend.samples.last else { print("no sample could be read"); exit(1) }

    for kind in MemoryKind.allCases {
        guard let report = MemoryKindReport.make(kind, samples: trend.samples) else {
            check("\(kind.title) has a screen", false, "no report")
            continue
        }
        print("== \(kind.title)  (\(kind.link))")
        print("   \(report.headline)  \(report.caption)")
        for fact in report.facts { print("   \(fact.label): \(fact.value)") }
        for chart in report.charts {
            print("   chart \"\(chart.title)\":")
            for series in chart.series {
                let last = series.points.last.map { chart.unit == .bytes ? MemorySize.text(Int64($0.value)) : MemoryKindReport.rateText($0.value) } ?? "-"
                print("     \(series.name)\(series.dashed ? " (dashed)" : ""): \(series.points.count) points, now \(last)")
            }
        }
        if !report.pressure.isEmpty { print("   pressure now: \(MemoryKindReport.pressureWord(report.pressure.last?.level ?? 1))") }
        for note in report.notes.prefix(1) { print("   note: \(note)") }
        print()
        check("\(kind.title): a headline, facts, and a sentence on what cannot be shown",
              !report.headline.isEmpty && !report.facts.isEmpty && !report.notes.isEmpty, "\(report.facts.count) facts")
        check("\(kind.title): every chart has points on one axis", report.charts.allSatisfy { $0.series.allSatisfy { !$0.points.isEmpty } },
              "\(report.charts.count) chart(s)")
    }

    // The block's figures and the screens' come from the same arithmetic (`MemoryBreakdown.make`). Memory moves between two
    // looks seconds apart, so equality is proved where it can be: the block, a sample and the block again, microseconds
    // apart; whenever the block holds still across the sample, the sample must be exactly it.
    var held = 0
    var differ = 0
    for _ in 0..<200 {
        guard let first = MemoryBreakdown.current(), let one = MemorySample.read(graphics: nil), let second = MemoryBreakdown.current() else { continue }
        if first == second {
            held += 1
            if one.breakdown != first { differ += 1 }
        }
    }
    check("the block's figures equal the screens' whenever memory holds still across a sample", held >= 1 && differ == 0,
          "\(held) quiet moments in 200 tries, \(differ) differ")
    check("used plus cached plus free is the installed memory", latest.breakdown.usedBytes + latest.breakdown.cachedBytes + latest.breakdown.freeBytes >= latest.breakdown.totalBytes,
          "\(MemorySize.text(latest.breakdown.usedBytes + latest.breakdown.cachedBytes + latest.breakdown.freeBytes)) of \(MemorySize.text(latest.breakdown.totalBytes))")

    // how a size is written, by where it is shown: the decimals are a maximum, never padding
    let gib = Int64(1_073_741_824), mib = Int64(1_048_576)
    func gb(_ x: Double) -> Int64 { Int64(x * Double(gib)) }
    check("exactly 5 GB is \"5 GB\" in every style, never \"5.00 GB\"",
          [ByteSize.Style.axis, .figure, .headline, .cell].allSatisfy { ByteSize.text(5 * gib, $0) == "5 GB" }, ByteSize.text(5 * gib, .axis))
    check("5.4 GB and 18.63 GB keep what they have in an axis or a figure list",
          ByteSize.text(gb(5.4), .axis) == "5.4 GB" && ByteSize.text(gb(18.63), .axis) == "18.63 GB" && ByteSize.text(gb(23.64), .figure) == "23.64 GB",
          "\(ByteSize.text(gb(5.4), .axis)), \(ByteSize.text(gb(18.63), .axis)), \(ByteSize.text(gb(23.64), .figure))")
    check("a headline and a cell have one decimal in GB", ByteSize.text(gb(10.44), .headline) == "10.4 GB" && ByteSize.text(gb(3.44), .cell) == "3.4 GB",
          "\(ByteSize.text(gb(10.44), .headline)), \(ByteSize.text(gb(3.44), .cell))")
    check("megabytes have none, a cell under a megabyte is \"<1 MB\"",
          ByteSize.text(827 * mib, .cell) == "827 MB" && MemorySize.text(mib / 2) == "<1 MB" && MemorySize.text(3 * mib + mib / 3) == "3 MB",
          "\(ByteSize.text(827 * mib, .cell)), \(MemorySize.text(mib / 2)), \(MemorySize.text(3 * mib + mib / 3))")
    check("a rate has one decimal under 10 and none above",
          ByteSize.rate(4.2 * 1_048_576) == "4.2 MB/s" && ByteSize.rate(286 * 1_048_576) == "286 MB/s" && ByteSize.rate(340 * 1024) == "340 KB/s"
            && ByteSize.rate(2 * 1_048_576) == "2 MB/s", "\(ByteSize.rate(4.2 * 1_048_576)), \(ByteSize.rate(286 * 1_048_576)), \(ByteSize.rate(340 * 1024))")

    // the history
    let long = MemoryTrend()
    let t0 = Date()
    for step in 0..<1_000 { long.append(sample(latest, at: t0.addingTimeInterval(Double(step) * 2))) }
    check("the history keeps 900 samples (30 minutes at 2 s)", long.samples.count == MemoryTrend.capacity && MemoryTrend.capacity == 900,
          "\(long.samples.count) kept")
    check("  ... the oldest ones went", long.samples.first?.date == t0.addingTimeInterval(200), "starts at the 101st")
    let stale = MemoryTrend()
    stale.replace(with: [sample(latest, at: Date().addingTimeInterval(-300))])
    stale.begin()
    check("closed for over a minute, the history starts again", stale.samples.first.map { Date().timeIntervalSince($0.date) < 5 } != false && stale.samples.count <= 1,
          "\(stale.samples.count) old sample(s) kept")
    stale.end()
    let fresh = MemoryTrend()
    fresh.replace(with: [sample(latest, at: Date().addingTimeInterval(-20))])
    fresh.begin()
    check("closed for 20 seconds, the history goes on", fresh.samples.count >= 1 && (fresh.samples.first.map { Date().timeIntervalSince($0.date) > 10 } ?? false), "the old sample is still there")
    fresh.end()

    // rates
    var earlier = latest
    earlier = sample(latest, at: latest.date.addingTimeInterval(-2), swapOuts: latest.swapOuts &- 100, swapIns: latest.swapIns &- 40)
    check("a swap rate is pages per second times the page size", abs(latest.swapOutRate(since: earlier) - 100 * Double(latest.pageSize) / 2) < 1,
          MemoryKindReport.rateText(latest.swapOutRate(since: earlier)))
    let backwards = sample(latest, at: latest.date.addingTimeInterval(-2), swapOuts: latest.swapOuts + 5)
    check("a counter that went backwards gives zero, never a negative rate", latest.swapOutRate(since: backwards) == 0, "0")

    // who holds the most compressed memory
    let fixed = """
    Processes: 958 total
    PhysMem: 30G used

    PID    COMMAND          MEM   CMPRS USER
    40271  OrbStack Helper  5543M 3072M helderrodrigues
    79735  node             2270M 2249M+ helderrodrigues
    432    WindowServer     777M  446M- _windowserver
    24808  Opera Helper (Re 439M  7904K root
    garbage line
    """
    let parsed = CompressedHolders.parse(fixed)
    check("`top`'s table is read: names with spaces, K and M, change markers",
          parsed.count == 4 && parsed[0].command == "OrbStack Helper" && parsed[0].compressedBytes == 3072 * 1_048_576
            && parsed[1].compressedBytes == 2249 * 1_048_576 && parsed[2].user == "_windowserver"
            && parsed[3].command == "Opera Helper (Re" && parsed[3].compressedBytes == 7904 * 1024, "\(parsed.map(\.command))")
    check("a line that is not a row, and text before the table, are left out", CompressedHolders.parse("nothing here").isEmpty, "no rows")
    let real = CompressedHolders.read()
    print("   the real top: \(real.holders.count) rows, \(real.failure ?? "no failure")")
    if let first = real.holders.first {
        print("   biggest: \(first.command) (\(first.user)) \(MemorySize.text(first.footprintBytes)), \(MemorySize.text(first.compressedBytes)) compressed")
    }
    check("the real `top` gives rows for this Mac, macOS's own among them", real.failure == nil && real.holders.count >= 10, "\(real.holders.count) rows")
    exit(failed ? 1 : 0)
}

private func sample(_ base: MemorySample, at date: Date, swapOuts: UInt64? = nil, swapIns: UInt64? = nil) -> MemorySample {
    MemorySample(date: date, breakdown: base.breakdown, swapUsedBytes: base.swapUsedBytes, swapTotalBytes: base.swapTotalBytes,
                 pressureLevel: base.pressureLevel, graphicsBytes: base.graphicsBytes, swapIns: swapIns ?? base.swapIns,
                 swapOuts: swapOuts ?? base.swapOuts, compressions: base.compressions, decompressions: base.decompressions,
                 pageSize: base.pageSize)
}
