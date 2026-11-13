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
    for section in panel.sections {
        print("\(section.title) · \(section.groups) groups · \(section.processes) processes · \(section.totalText)")
        for row in section.rows {
            let offer = PanelStop.offer(for: row.group)
            let state: String
            switch offer {
            case .quit: state = "Quit"
            case .stop: state = "Stop"
            case .locked(let reason): state = "lock: \(reason.prefix(60))"
            }
            let icon = GroupIcon.image(for: row.group) != nil ? "icon" : "symbol"
            print("    \(row.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(row.sizeText.padding(toLength: 9, withPad: " ", startingAt: 0)) \(icon.padding(toLength: 7, withPad: " ", startingAt: 0)) \(state)")
        }
        if section.more > 0 { print("    … \(section.more) more in Monitor (\(section.category.monitorLink))") }
    }
    print("\nMEMORY TAB — the panel's figures against vm_stat and sysctl, read together:\n")
    guard let memory = PanelMemory.take() else { print("the Mac would not say"); exit(1) }

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
    let b = memory.breakdown
    line("Physical Memory", panel: b.totalBytes, other: Int64(ProcessInfo.processInfo.physicalMemory), source: "physicalMemory")
    line("Memory Used", panel: b.usedBytes, other: vApp + vWired + vCompressed, source: "vm_stat")
    line("Cached Files", panel: b.cachedBytes, other: vCached, source: "vm_stat")
    line("Swap Used", panel: memory.swapUsedBytes, other: sysctlSwap, source: "vm.swapusage")
    line("App Memory", panel: b.appBytes, other: vApp, source: "vm_stat")
    line("Wired Memory", panel: b.wiredBytes, other: vWired, source: "vm_stat")
    line("Compressed", panel: b.compressedBytes, other: vCompressed, source: "vm_stat")
    print("    pressure          panel \(memory.pressurePercent.map(String.init) ?? "—") %   (100 − kern.memorystatus_level \(level))")
    print("\nthe panel's words: Physical Memory \(memory.physicalText) · Memory Used \(memory.usedText) · Cached Files \(memory.cachedText) · Swap Used \(memory.swapText) · App Memory \(memory.appText) · Wired Memory \(memory.wiredText) · Compressed \(memory.compressedText)")
    exit(0)
}
