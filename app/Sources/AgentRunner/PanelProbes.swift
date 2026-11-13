import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-panel` prints what the menu-bar panel's two tabs would show, as text:
// the Monitor tab's groups by category, and the Memory tab's figures next to what `vm_stat` and
// `sysctl vm.swapusage` say at the same moment (the numbers Activity Monitor reads).

/// A command's output.
private func output(_ path: String, _ arguments: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = arguments
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    return text
}

private func mb(_ bytes: Int64) -> String { String(format: "%8.1f MB", Double(bytes) / 1_048_576) }

@MainActor func probePanel() -> Never {
    print("MONITOR TAB — the groups by category, heaviest first (the same census as Monitor):\n")
    let panel = MenuPanelModel(census: MemoryCensus.take())
    for scope in [nil, CensusGroup.Category.apps, .tools, .system] {
        let shown = panel.nodes(in: scope)
        print("\(scope?.shortTitle ?? Names.Monitor.everything) · \(panel.groupCount(in: scope)) groups")
        for node in shown.nodes.prefix(8) {
            let state: String
            if let group = node.group {
                switch PanelStop.offer(for: group) {
                case .quit: state = "Quit"
                case .stop: state = "Stop"
                case .locked(let reason): state = "lock: \(reason.prefix(50))"
                }
            } else { state = "" }
            let inside = node.children.map { " ▸ \($0.count) inside: \($0.prefix(3).map(\.name).joined(separator: ", "))" } ?? ""
            print("    \(node.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(node.sizeText.padding(toLength: 9, withPad: " ", startingAt: 0)) \((node.detail ?? "").padding(toLength: 14, withPad: " ", startingAt: 0)) \(state)\(inside)")
        }
        if shown.more > 0 { print("    … \(shown.more) more in Monitor") }
    }
    print("\nMEMORY TAB — the panel's figures against vm_stat and sysctl, read together:\n")
    guard let breakdown = MemoryBreakdown.current() else { print("the Mac would not say"); exit(1) }
    let swapUsedNow = MemorySample.readSwap()?.used

    // vm_stat, the way Activity Monitor's definitions use it
    let text = output("/usr/bin/vm_stat", [])
    var pageSize: Int64 = 16384
    if let match = text.firstMatch(of: /page size of (\d+) bytes/), let size = Int64(match.1) { pageSize = size }
    func pages(_ label: String) -> Int64 {
        for line in text.split(separator: "\n") where line.hasPrefix(label) {
            let digits = line.drop { !$0.isNumber }.prefix { $0.isNumber }
            return (Int64(digits) ?? 0) * pageSize
        }
        return 0
    }
    let purgeable = pages("Pages purgeable")
    let anonymous = pages("Anonymous pages")
    let vApp = max(0, anonymous - purgeable)
    let vWired = pages("Pages wired down")
    let vCompressed = pages("Pages occupied by compressor")
    let vCached = pages("File-backed pages") + purgeable
    let swap = output("/usr/sbin/sysctl", ["vm.swapusage"])
    var sysctlSwap: Int64?
    if let match = swap.firstMatch(of: /used = ([\d.]+)([MGK])/), let value = Double(match.1) {
        sysctlSwap = Int64(value * (match.2 == "G" ? 1_073_741_824 : match.2 == "M" ? 1_048_576 : 1024))
    }
    let level = output("/usr/sbin/sysctl", ["-n", "kern.memorystatus_level"]).trimmingCharacters(in: .whitespacesAndNewlines)

    func line(_ name: String, panel: Int64?, other: Int64?, source: String) {
        let diff = (panel != nil && other != nil) ? String(format: "%+7.1f MB", Double(panel! - other!) / 1_048_576) : "       —"
        print("    \(name.padding(toLength: 16, withPad: " ", startingAt: 0)) panel \(panel.map(mb) ?? "—")   \(source.padding(toLength: 14, withPad: " ", startingAt: 0)) \(other.map(mb) ?? "—")   difference \(diff)")
    }
    let b = breakdown
    line("Physical Memory", panel: b.totalBytes, other: Int64(ProcessInfo.processInfo.physicalMemory), source: "physicalMemory")
    line("Memory Used", panel: b.usedBytes, other: vApp + vWired + vCompressed, source: "vm_stat")
    line("Cached Files", panel: b.cachedBytes, other: vCached, source: "vm_stat")
    line("Swap Used", panel: swapUsedNow, other: sysctlSwap, source: "vm.swapusage")
    line("App Memory", panel: b.appBytes, other: vApp, source: "vm_stat")
    line("Wired Memory", panel: b.wiredBytes, other: vWired, source: "vm_stat")
    line("Compressed", panel: b.compressedBytes, other: vCompressed, source: "vm_stat")
    print("    pressure          level \(MemoryKindReport.pressureWord(MemoryTrend.shared.pressureLevel)) (kern.memorystatus_level \(level))")
    print("\nthe panel's words: Physical Memory \(ByteSize.text(b.totalBytes, .figure)) · Memory Used \(ByteSize.text(b.usedBytes, .figure)) · Cached Files \(ByteSize.text(b.cachedBytes, .figure)) · Swap Used \(swapUsedNow.map { ByteSize.text($0, .figure) } ?? "—") · App Memory \(ByteSize.text(b.appBytes, .figure)) · Wired Memory \(ByteSize.text(b.wiredBytes, .figure)) · Compressed \(ByteSize.text(b.compressedBytes, .figure))")
    exit(0)
}

// `agent-runner --probe-pressure`: the pressure graph's two numbers are recorded per sample and carried to the bands:
// the HEIGHT (how much pressure, 0 to 100, from `kern.memorystatus_level`) and the COLOUR (the kernel's state).
// Judges itself on a real sample and on a fixture history with a warning stretch; exits 1 when a rule breaks.
@MainActor func probePressure() -> Never {
    var failed = false
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("  \(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : ": \(detail)")")
        if !ok { failed = true }
    }
    // a real sample: a percentage in range, equal to 100 minus the sysctl read now (the level can move by a point or two between reads)
    guard let real = MemorySample.read(graphics: nil) else { print("the Mac would not say"); exit(1) }
    let level = Int(output("/usr/sbin/sysctl", ["-n", "kern.memorystatus_level"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
    check("a sample records how much pressure there is, 0 to 100", (0...100).contains(real.pressurePercent), "\(real.pressurePercent) %")
    check("and it is 100 minus kern.memorystatus_level", abs(real.pressurePercent - (100 - level)) <= 3,
          "sample \(real.pressurePercent), 100 − \(level) = \(100 - level)")
    check("and the state is one the kernel reports", [1, 2, 4].contains(real.pressureLevel), "level \(real.pressureLevel)")

    // a history with a warning stretch in the middle
    let start = Date().addingTimeInterval(-120)
    let history: [MemorySample] = (0..<60).map { step in
        let level = (20..<40).contains(step) ? 2 : 1
        return MemorySample(date: start.addingTimeInterval(Double(step) * 2), breakdown: real.breakdown,
                            swapUsedBytes: real.swapUsedBytes, swapTotalBytes: real.swapTotalBytes, pressureLevel: level,
                            pressurePercent: level == 2 ? 70 : 30, graphicsBytes: nil, swapIns: 0, swapOuts: 0,
                            compressions: 0, decompressions: 0, pageSize: real.pageSize)
    }
    guard let report = MemoryKindReport.make(.free, samples: history) else { print("no report"); exit(1) }
    let calm = report.pressure.filter { $0.level == 1 }, warn = report.pressure.filter { $0.level == 2 }
    check("every sample becomes a band with its height and its state", report.pressure.count == 60, "\(report.pressure.count) bands")
    check("the warning stretch is its own state, 20 bands", warn.count == 20, "\(warn.count)")
    check("and its bars are taller than the calm ones",
          (warn.map(\.percent).min() ?? 0) > (calm.map(\.percent).max() ?? 100),
          "warning \(warn.map(\.percent).min() ?? 0)…\(warn.map(\.percent).max() ?? 0) %, calm \(calm.map(\.percent).min() ?? 0)…\(calm.map(\.percent).max() ?? 0) %")
    print(failed ? "the pressure graph's data FAILED a case" : "all cases passed")
    exit(failed ? 1 : 0)
}
