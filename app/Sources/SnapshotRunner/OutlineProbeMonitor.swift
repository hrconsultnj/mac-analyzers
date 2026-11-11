import AppKit
import Foundation
import SettingsFeature
import SwiftUI

/// `monitor:<case>`: the REAL Monitor table (`MonitorOutline`, its model, its filter and sort rule) on rows from
/// the real process table, driven the way a person and the clock drive it. Zero reentrancy warnings is the
/// driver's to count (`scripts/monitor-probe.sh`). Cases: first (the table exists before it has rows), ticks,
/// resort, search, tabs, open1, openAll, churn (processes start and end inside an open group), soak.
@MainActor
enum ProbeMonitor {
    static func run(_ name: String, _ options: ProbeOptions) -> Int32 {
        let probe = MonitorProbe()
        let harness = ProbeHarness(probe.view, size: NSSize(width: 900, height: 600))

        /// Runs an async step to its end on the main loop.
        func wait(_ step: @escaping @MainActor () async -> Void) {
            var done = false
            Task { @MainActor in await step(); done = true }
            let start = now()
            while !done && now() - start < 60 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        }
        func loaded() { wait { await probe.load() }; _ = settle(); spin(0.5) }

        switch name {
        case "first":
            mark("begin first")
            loaded()
            mark("end first")
        case "ticks":
            loaded()
            probe.openFirstGroup(); _ = settle()
            mark("begin ticks")
            for _ in 0..<5 { wait { await probe.tick() }; _ = settle(); spin(0.2) }
            mark("end ticks")
        case "resort":
            loaded(); probe.openAll(); _ = settle()
            mark("begin resort")
            for key in ["cpu", "name", "memory", "cpu", "memory"] { probe.sort(by: key); _ = settle(); spin(0.2) }
            wait { await probe.refreshNow() }; _ = settle()
            mark("end resort")
        case "search":
            loaded(); probe.openFirstGroup(); _ = settle()
            mark("begin search")
            for text in ["chrome", "node", "", "zzzz", ""] { probe.filter(text); _ = settle(); spin(0.2) }
            mark("end search")
        case "tabs":
            loaded(); probe.openFirstGroup(); _ = settle()
            mark("begin tabs")
            for scope in ["apps", "tools", "system", "everything", "apps", "everything"] { probe.showScope(scope); _ = settle(); spin(0.2) }
            mark("end tabs")
        case "open1":
            loaded()
            mark("begin open1")
            probe.openFirstGroup(); _ = settle()
            mark("end open1")
        case "openAll":
            loaded()
            mark("begin openAll")
            probe.openAll(); _ = settle(); spin(0.5)
            mark("end openAll")
        case "churn":
            loaded(); probe.openAll(); _ = settle()
            mark("begin churn")
            for _ in 0..<6 { probe.churn(); _ = settle(); spin(0.2) }
            mark("end churn")
        case "soak":
            loaded(); probe.openAll(); _ = settle()
            let end = now() + Double(options.seconds)
            var step = 0
            mark("begin soak")
            while now() < end {
                step += 1
                wait { await probe.tick() }
                if step % 3 == 0 { probe.churn() }
                if step % 4 == 0 { probe.sort(by: ["cpu", "name", "memory"][step / 4 % 3]) }
                if step % 6 == 0 { probe.filter(step % 12 == 0 ? "" : "node") }
                spin(5)
            }
            mark("end soak")
        default:
            FileHandle.standardError.write(Data("unknown monitor case \(name)\n".utf8))
            return 2
        }
        say("monitor:\(name) rows=\(probe.rowCount) groups=\(probe.groupCount) open=\(probe.openCount) table rows=\(harness.outline.numberOfRows)")
        return probe.isLoaded ? 0 : 1
    }
}
