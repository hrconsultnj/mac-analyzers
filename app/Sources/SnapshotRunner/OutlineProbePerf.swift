import AppKit
import Foundation
import SwiftUI
import UIComponents

/// A5: timings at 6,000 rows (1,000 x 5, all open), in the measurement's terms.
@MainActor
enum ProbePerf {
    static func run(_ options: ProbeOptions) -> Int32 {
        let cpuBefore = cpuMilliseconds()
        let model = ProbeModel(rows: makeProbeRows(parents: options.parents, kids: options.kids, levels: options.levels))
        let harness = ProbeHarness(ProbeScreen(model: model, hosted: options.hosted))
        guard let outline = harness.outline else { say("FAIL no outline view found"); return 1 }
        let cpuAtAppear = cpuMilliseconds() - cpuBefore
        var results: [(String, Double)] = [("appear", harness.appearMilliseconds), ("appearCpu", cpuAtAppear)]
        func time(_ label: String, _ body: () -> Void) {
            let start = now(), cpuStart = cpuMilliseconds()
            body()
            _ = settle()
            results.append((label, (now() - start) * 1000 - 3))
            results.append((label + "Cpu", cpuMilliseconds() - cpuStart))
        }
        time("expandAll") { ProbeActions.perform("expandAll", model: model, outline: outline) }
        let rows = outline.numberOfRows

        var steps: [Double] = []
        var row = 0
        while row < rows {
            let start = now()
            outline.scrollRowToVisible(row)
            outline.layoutSubtreeIfNeeded()
            harness.window.contentView?.displayIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            steps.append((now() - start) * 1000)
            row += 150
        }
        let sorted = steps.sorted()
        results.append(("scrollMean", steps.reduce(0, +) / Double(max(steps.count, 1))))
        results.append(("scrollP95", sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]))
        outline.scrollRowToVisible(0)
        _ = settle()

        // what the probe's own model costs for the same edits, so the steps below can be read net of it
        var copy = model.rows
        var start = cpuMilliseconds()
        ProbeActions.bumpValues(&copy)
        results.append(("valuesModelCpu", cpuMilliseconds() - start))
        start = cpuMilliseconds()
        copy.sort { $0.mem > $1.mem }
        results.append(("resortModelCpu", cpuMilliseconds() - start))

        for action in ["values", "resort", "addChild", "removeChild", "filter10", "filterBack"] {
            time(action) { ProbeActions.perform(action, model: model, outline: outline) }
        }
        let line = results.map { "\($0.0)=\(String(format: "%.1f", $0.1))" }.joined(separator: " ")
        say("perf rows=\(rows) hosted=\(options.hosted) \(line)")
        return 0
    }
}
