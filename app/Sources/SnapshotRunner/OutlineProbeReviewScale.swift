@_spi(TestSupport) import AnalyzersKit
import AppKit
import Foundation
import SettingsFeature
import SwiftUI
import UIComponents

/// `review:scale`: what the review costs at Downloads' size (6,154 rows, a two-line name cell), step
/// by step, in wall time and in this thread's CPU time, with the load average beside it: first
/// appearance, a tick, Select All, a re-sort, `updateChoosable` on one row.
extension ProbeReview {
    static func scale(_ options: ProbeOptions) -> Int32 {
        let count = 6154
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        let probe = ReviewFixtureProbe(downloads: count)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "ma-review-scale-\(getpid())", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let jobs = JobStore(ledger: JobLedger(url: scratch.appending(path: "jobs.jsonl")))

        let wall0 = now(), cpu0 = cpuMilliseconds()
        let harness = ProbeHarness(probe.view.environment(jobs), size: NSSize(width: 900, height: 700))
        let appear = (now() - wall0) * 1000, appearCpu = cpuMilliseconds() - cpu0
        guard let outline = harness.outline else { say("FAIL no outline"); return 1 }
        _ = settle(); spin(0.3)

        var results: [(String, Double, Double)] = [("appear", appear, appearCpu)]
        func time(_ label: String, _ body: () -> Void) {
            let w = now(), c = cpuMilliseconds()
            body()
            _ = settle()
            results.append((label, (now() - w) * 1000 - 3, cpuMilliseconds() - c))
        }
        mark("begin review:scale")
        let closedRows = outline.numberOfRows
        // a tick on a group's box (the group has about 2,000 members)
        time("tickGroup") { ProbeChecks.tickButton(outline, row: 1)?.performClick(nil) }
        // Expand All: every group opens, 6,159 rows
        time("expandAll") { outline.expandItem(nil, expandChildren: true) }
        let shown = outline.numberOfRows
        // a tick on one row
        let leaf = (0..<outline.numberOfRows).first { outline.level(forRow: $0) == 1 } ?? 1
        time("tickRow") { ProbeChecks.tickButton(outline, row: leaf)?.performClick(nil) }
        time("selectNone") { probe.barSelectNone() }
        time("selectAll") { probe.barSelectAll() }
        time("resort") { outline.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)] }
        time("updateChoosable") { probe.ended("/Users/example/Downloads/file-100.dmg") }
        mark("end review:scale")
        let line = results.map { String(format: "%@=%.1f/%.1f", $0.0, $0.1, $0.2) }.joined(separator: " ")
        say(String(format: "scale rows=%d closed=%d open=%d (wall ms / cpu ms) %@ load=%.1f/%.1f/%.1f approved=%d", count, closedRows, shown, line,
                   loads[0], loads[1], loads[2], probe.report().approved.count))
        return 0
    }
}
