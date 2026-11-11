import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-monitor` prints Monitor's table from the live process
// table: the groups biggest first with CPU read over a real second, the top
// groups opened one level, then a second refresh merged in place to show the
// order does not move. `--probe-stop-targets` prints what a group Stop would
// offer (every separate program, locked or not) and proves the guards:
// a stale start time is refused, a coding-agent session cannot be stopped.
// Nothing is stopped except throwaway `sleep` processes this probe starts.

private func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width - 1)) + " " : text + String(repeating: " ", count: width - text.count)
}

private func show(_ rows: [MonitorRow], depth: Int, limit: Int, openTop: Int) {
    for (index, row) in rows.prefix(limit).enumerated() {
        line(row, depth: depth)
        if depth < 2, index < openTop { show(row.children, depth: depth + 1, limit: 6, openTop: 0) }
    }
}

private func line(_ row: MonitorRow, depth: Int) {
    let indent = String(repeating: "    ", count: depth)
    let name = indent + row.name
    let lock = row.lockedReason.map { _ in "🔒" } ?? ""
    print(pad(name, 40) + pad(row.detail, 38) + pad(row.memoryText, 10) + pad(row.cpuText, 8)
          + pad(row.pid.map(String.init) ?? "", 8) + (row.stopVerb ?? "") + lock)
}

func probeMonitor() -> Never {
    var meter = CPUMeter()
    let started = Date()
    let census = MemoryCensus.take()
    let censusSeconds = Date().timeIntervalSince(started)
    let pids = census.groups.flatMap { $0.members.map { Int32($0.pid) } }
    _ = meter.look(at: ProcTable.cpuTimes(of: pids))
    Thread.sleep(forTimeInterval: 1.0)
    let cpu = meter.look(at: ProcTable.cpuTimes(of: pids))

    let built = Date()
    let rows = MonitorTree.sorted(MonitorTree.rows(census: census, cpu: cpu), by: .biggestFirst)
    print("census \(String(format: "%.2f", censusSeconds)) s, tree \(String(format: "%.2f", Date().timeIntervalSince(built))) s: \(rows.count) groups, \(census.processCount) processes, CPU read for \(cpu.count) of them")
    if let memory = census.breakdown {
        print("\(MemorySize.text(memory.usedBytes)) in use of \(MemorySize.text(memory.totalBytes)) · app \(MemorySize.text(memory.appBytes)) · wired \(MemorySize.text(memory.wiredBytes)) · compressed \(MemorySize.text(memory.compressedBytes)) · cached \(MemorySize.text(memory.cachedBytes)) · free \(MemorySize.text(memory.freeBytes))")
    }
    print(pad("NAME", 40) + pad("WHAT IT IS", 38) + pad("MEMORY", 10) + pad("CPU", 8) + pad("PID", 8) + "STOP")
    show(rows, depth: 0, limit: 12, openTop: 3)

    // the levels: a tab per kind (with its total), groups, and no repeated title inside a group
    print("\ntabs:")
    for total in MonitorTree.categoryTotals(rows) {
        print("  \(total.category.rawValue.padding(toLength: 34, withPad: " ", startingAt: 0)) \(total.groups) groups, \(total.processes) processes, \(MemorySize.text(total.bytes))")
    }
    var repeated: [String] = []
    // processes of one name are told apart by their pid column; groups, parts and programs by their title
    func check(_ rows: [MonitorRow], under parent: String) {
        let names = rows.filter { $0.kind != .process }.map(\.name)
        let dupes = Dictionary(grouping: names, by: { $0 }).filter { $1.count > 1 }.keys
        for dupe in dupes { repeated.append("\(parent) › \(dupe)") }
        for row in rows where row.kind != .process { check(row.children, under: row.name) }
    }
    // a name may recur across the tabs (a tool called bash and macOS's own bash); never inside one
    for category in CensusGroup.Category.allCases { check(rows.filter { $0.category == category }, under: "\(category.rawValue) tab") }
    print(repeated.isEmpty ? "no title repeats inside a group" : "TITLE REPEATS inside: \(repeated.joined(separator: ", "))")

    // a refresh: values change in place, the order does not
    let again = MemoryCensus.take()
    let merged = MonitorTree.merge(rows, with: MonitorTree.rows(census: again, cpu: cpu))
    let before = rows.map(\.id)
    let after = merged.map(\.id)
    let survivors = after.filter(before.contains)
    let stable = survivors == before.filter(after.contains)
    print("\nrefresh merged in place: \(merged.count) groups; survivors keep their order: \(stable ? "yes" : "NO")"
          + "; appended at the end: \(after.filter { !before.contains($0) }.count); dropped: \(before.filter { !after.contains($0) }.count)")

    let byCPU = MonitorTree.sorted(rows, by: MonitorTree.Sort(.cpu, ascending: false)).prefix(5)
    print("busiest right now: " + byCPU.map { "\($0.name) \($0.cpuText)" }.joined(separator: ", "))
    exit(stable && repeated.isEmpty ? 0 : 1)
}

// `agent-runner --probe-agents` proves the app and the engine read one list of
// coding agents and agree on it: a corpus built from every line of
// `lib/coding-agents.tsv` (plus lines that must NOT match) is classified by the
// app (`CodingAgentHosts`) and by `lib/live-sessions.sh` under bash and under
// /bin/bash, and any difference fails the probe.
func probeAgents(_ args: [String]) -> Never {
    let rootArg = args.firstIndex(of: "--root").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    let root = rootArg.map { URL(fileURLWithPath: $0) } ?? AnalyzersPaths.suiteRoot
    let list = root.appending(path: "lib/coding-agents.tsv")
    let text = (try? String(contentsOf: list, encoding: .utf8)) ?? ""
    let rows = text.split(whereSeparator: \.isNewline)
        .filter { !$0.hasPrefix("#") }.map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    // one corpus line per list line, remembering which line it came from
    var corpus: [String] = []
    var origin: [Int: (agent: String, kind: String)] = [:]
    for row in rows where row.count >= 3 {
        let line: String
        switch row[1] {
        case "exe": line = "/opt/tools/bin/\(row[2]) --session abc"
        case "fragment": line = "/opt/\(row[2])/run \(row.count >= 4 ? row[3] : "") --x"
        case "ignore": line = "\(row[2]) claude --x"
        default: continue
        }
        origin[corpus.count] = (row[0], row[1])
        corpus.append(line)
    }
    corpus += ["/Applications/Antigravity.app/Contents/MacOS/Antigravity",
               "/Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper",
               "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT", "/usr/bin/ssh host", "vim notes.txt",
               "/Applications/Claude.app/Contents/MacOS/Claude",
               "node /Users/x/Projects/app/node_modules/.bin/vite"]
    let numbered = corpus.enumerated().map { "\($0.offset + 100) \($0.element)" }

    /// What the engine's filter recognises in the corpus, with this copy of the lib and its list.
    func engineSide(_ shell: String, script: URL) -> Set<Int> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-c", "source '\(script.path)'; _live_session_filter"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        try? p.run()
        input.fileHandleForWriting.write(Data(numbered.joined(separator: "\n").utf8))
        try? input.fileHandleForWriting.close()
        let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return Set(out.split(separator: "\n").compactMap { Int($0) }.map { $0 - 100 })
    }

    var ok = true
    let appSide = CodingAgentHosts.probe(listAt: list)
    let swiftSide = Set(numbered.indices.filter { appSide.classify(corpus[$0]) != nil })
    print("list: \(list.path)")
    print("agents in the list: \(appSide.agentNames.joined(separator: ", "))")
    print("corpus: \(corpus.count) command lines; the app recognises \(swiftSide.count) as session roots")

    // Equal counts are not proof: 0 equals 0. Every list line must recognise ITS OWN corpus line
    // (and an ignore line must not), so a list that matches nothing fails here.
    let silent = origin.filter { index, line in line.kind == "ignore" ? swiftSide.contains(index) : !swiftSide.contains(index) }
    for (index, line) in silent.sorted(by: { $0.key < $1.key }) {
        ok = false
        print("    FAIL the \(line.kind) line for \(line.agent) does not behave as written: \(corpus[index])")
    }
    if silent.isEmpty { print("every list line recognises its own corpus line (ignore lines do not)") }

    // the same list saved with Windows line endings must behave identically on both sides
    let scratch = FileManager.default.temporaryDirectory.appending(path: "ma-probe-agents-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let crlf = scratch.appending(path: "coding-agents.tsv")
    try? text.replacingOccurrences(of: "\n", with: "\r\n").write(to: crlf, atomically: true, encoding: .utf8)
    try? FileManager.default.copyItem(at: root.appending(path: "lib/live-sessions.sh"), to: scratch.appending(path: "live-sessions.sh"))
    let crlfApp = CodingAgentHosts.probe(listAt: crlf)
    let crlfSwift = Set(numbered.indices.filter { crlfApp.classify(corpus[$0]) != nil })
    let appCRLF = crlfSwift == swiftSide
    ok = ok && appCRLF
    print("a copy with Windows line endings: the app recognises \(crlfSwift.count) — \(appCRLF ? "identical" : "DIFFERS")")

    for shell in ["/bin/bash", "/opt/homebrew/bin/bash"] where FileManager.default.isExecutableFile(atPath: shell) {
        let label = shell == "/bin/bash" ? "bash 3.2 (/bin/bash)" : "bash 5 (\(shell))"
        let shellSide = engineSide(shell, script: root.appending(path: "lib/live-sessions.sh"))
        let same = shellSide == swiftSide
        ok = ok && same
        print("\(label): recognises \(shellSide.count) — \(same ? "identical to the app" : "DIFFERS from the app")")
        for index in shellSide.symmetricDifference(swiftSide).sorted() {
            print("    disagreement: \(corpus[index])  app=\(swiftSide.contains(index)) engine=\(shellSide.contains(index))")
        }
        let crlfShell = engineSide(shell, script: scratch.appending(path: "live-sessions.sh"))
        let sameCRLF = crlfShell == swiftSide
        ok = ok && sameCRLF
        print("\(label), list with Windows line endings: recognises \(crlfShell.count) — \(sameCRLF ? "identical" : "DIFFERS: the engine's protection would be off")")
    }
    exit(ok ? 0 : 1)
}
