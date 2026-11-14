import Foundation
@_spi(TestSupport) import AnalyzersKit

// Memory Guard's rules engine, Watching only. Three commands:
//   agent-runner --check-rules [--root <checkout>] [--dir <rules folder>] [--local <file>]
//       reads plan.json, protected.json, kinds.json and rules.local.json and lists every rule with its state; exits 1 when
//       the plan, the protections or the person's changes have anything the engine cannot run.
//   agent-runner --rules-once [--write]
//       one look at the real process table: what each rule matches now and what the ladder would pick. Read only; with
//       --write the would-have rows are added to rule-outcomes.jsonl (run it under a throwaway HOME).
//   agent-runner --compare-legacy [--real] [--root <checkout>]
//       the guard script's own choice of what it may stop, against the engine's, on a recorded process table (the default)
//       or on this Mac's (--real, read only). The engine's set must be inside the script's.
//   agent-runner --probe-rules-fixture
//       the rules, the protections and the log on stand-in processes; fails when one of them breaks.

private func useCheckout(_ args: [String]) -> URL {
    let root = probeRoot(args)
    KindCatalog.use(file: root.appending(path: "memory-analyzer/rules/kinds.json"))
    CodingAgentHosts.useList(at: root.appending(path: "lib/coding-agents.tsv"))
    return root
}

private func option(_ args: [String], _ name: String) -> String? {
    args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
}

private func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width - 1)) + " " : text + String(repeating: " ", count: width - text.count)
}

// MARK: - --check-rules

func probeCheckRules(_ args: [String]) -> Never {
    let root = useCheckout(args)
    let dir = option(args, "--dir").map { URL(fileURLWithPath: $0) } ?? root.appending(path: "memory-analyzer/rules")
    GuardRules.use(directory: dir, local: option(args, "--local").map { URL(fileURLWithPath: $0) } ?? dir.appending(path: "rules.local.json"))
    let rules = GuardRules.load()
    var failed = false
    print("catalog: \(KindCatalog.current.isAvailable ? "\(KindCatalog.current.kinds.count) kinds" : "NOT USABLE: \(KindCatalog.current.problems.joined(separator: "; "))")")
    if !KindCatalog.current.isAvailable { failed = true }
    for problem in rules.problems { print("FAIL  \(problem)"); failed = true }
    for resolved in rules.resolved {
        let rule = resolved.rule
        var text = "  \(pad(rule.id, 28))\(pad(resolved.state.title, 10))\(pad(rule.selector, 20))"
        switch rule.shape {
        case .limit(let gb, let measure, let overFor, _): text += "over \(gb) GB per \(measure.rawValue), \(overFor) s, \(rule.action.rawValue)"
        case .step(let which, let mb): text += "step \(which.rawValue)\(mb.map { " \($0) MB" } ?? ""), \(rule.action.rawValue)"
        }
        if case .cantRun(let why) = resolved.state { text += "  — can't run: \(why)"; failed = true }
        if let note = resolved.note { text += "  — \(note)" }
        print(text)
    }
    print("\(rules.resolved.count) rules: "
          + ["acting", "watching", "off"].map { name in "\(rules.resolved.filter { $0.state.title.lowercased() == name }.count) \(name)" }.joined(separator: ", "))
    print(failed ? "FAIL" : "ok: every rule can run")
    exit(failed ? 1 : 0)
}

// MARK: - --rules-once

func probeRulesOnce(_ args: [String]) -> Never {
    _ = useCheckout(args)
    GuardRules.use(directory: probeRoot(args).appending(path: "memory-analyzer/rules"), local: nil)
    let rules = GuardRules.load()
    let groups = MemoryCensus.take().groups
    var state = RulesState()
    let result = RuleEvaluator.evaluate(rules: rules, groups: groups, facts: .live(), state: &state)
    if let skipped = result.skipped { print("nothing evaluated: \(skipped)") }
    print("\(groups.count) groups; pressure \(LiveStats.memoryPressure().label)")
    print("matching now:")
    for match in result.matches.sorted(by: { $0.unit.bytes > $1.unit.bytes }).prefix(40) {
        print("  \(pad(match.rule.id, 24))\(pad(match.state.title, 10))\(pad(match.kind.name, 24))\(pad(match.unit.name, 34))\(MemorySize.text(match.unit.bytes, .headline))  \(match.status)")
    }
    if result.matches.isEmpty { print("  nothing is over a limit") }
    print("the ladder, if memory ran out now:")
    for pick in result.picks {
        let pickText = pick.match.map { "\($0.unit.name) (\($0.kind.name), \(MemorySize.text($0.unit.bytes, .headline)))" } ?? pick.note ?? "nothing to pick"
        print("  \(pad(pick.rule.id, 26))\(pad(pick.state.title, 10))\(pickText)")
    }
    print("would-have rows to write: \(result.outcomes.count)")
    if args.contains("--write") { RuleOutcomes.append(result.outcomes); print("written to \(RuleOutcomes.file.path)") }
    exit(0)
}

// MARK: - --compare-legacy

private func guardPatterns(_ root: URL) -> (kill: String, protect: String)? {
    guard let text = try? String(contentsOf: root.appending(path: "memory-analyzer/memory-guard.sh"), encoding: .utf8) else { return nil }
    func value(_ name: String) -> String? {
        text.split(whereSeparator: \.isNewline).first { $0.hasPrefix("\(name)='") }.map { String($0.dropFirst(name.count + 2).dropLast()) }
    }
    guard let kill = value("KILLABLE_RE"), let protect = value("PROTECT_RE") else { return nil }
    return (kill, protect)
}

/// The guard script's own choice, from lib/guard-select.sh run by bash on the table: pids, in table order.
private func scriptCandidates(root: URL, psLines: String, exempt: Set<Int>, patterns: (kill: String, protect: String)) -> [Int] {
    let script = "source \"$1/lib/guard-select.sh\"; guard_select_candidates \"$2\" \"$3\" \"$4\" \"$5\" \"\""
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", script, "guard", root.path, patterns.kill, patterns.protect, "1", exempt.map(String.init).joined(separator: " ")]
    let input = Pipe(), output = Pipe()
    process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    input.fileHandleForWriting.write(Data(psLines.utf8)); try? input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { $0.split(separator: "\t").first.flatMap { Int($0) } }
}

/// A recorded table: pid, ppid, resident KB, the census category, the command line.
private struct TableRow { let pid: Int; let ppid: Int; let rssKB: Int; let category: CensusGroup.Category; let args: String }

private let recordedTable = """
# pid<TAB>ppid<TAB>rss_kb<TAB>category<TAB>args       (a recorded table: what a Mac running a coding session looks like)
1000\t1\t4194304\ttools\t/Users/x/.local/bin/claude --resume
1001\t1000\t2097152\ttools\tnode /opt/mcp/server-memory/index.js
1002\t1001\t900000\ttools\tnode /opt/work/dev-server.js
3000\t1\t7340032\ttools\tnode /Users/x/web/node_modules/.bin/vite
3001\t1\t1258291\ttools\tnode /Users/x/api/server.js
3002\t1\t307200\ttools\tnpx -y some-tool
3003\t1\t3145728\ttools\t/usr/bin/python3 /Users/x/app.py
3004\t1\t921600\ttools\tnode /Users/x/p/node_modules/jest-worker/build/workers/processChild.js
3005\t1\t2097152\tapps\t/Applications/Opera.app/Contents/Frameworks/Opera Helper (Renderer).app/Contents/MacOS/Opera Helper (Renderer) --type=renderer
3006\t1\t800000\tapps\t/Applications/Visual Studio Code.app/Contents/Resources/app/copilot-runtime --headless --stdio
3007\t1\t1500000\tapps\t/Users/x/Library/Caches/ms-playwright/chromium-1/chrome-mac/Chromium.app/Contents/MacOS/Chromium --headless
3008\t1\t900000\ttools\t/Users/x/bin/invite-cleanup --all
3009\t1\t600000\ttools\t/Users/x/.codex/packages/standalone/codex --session
3010\t3009\t700000\ttools\tnode /opt/mcp/codex-tools/server.js
400\t1\t900000\ttools\tnode /low/pid.js
"""

private func readTable(_ text: String) -> [TableRow] {
    text.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("#") }.compactMap { line in
        let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 5, let pid = Int(f[0]), let ppid = Int(f[1]), let rss = Int(f[2]) else { return nil }
        return TableRow(pid: pid, ppid: ppid, rssKB: rss, category: CensusGroup.Category(rawValue: f[3]) ?? .tools, args: f[4])
    }
}

/// The comparison itself: the script's choice against the engine's on a table. Returns the printable lines and whether it holds.
private func compare(_ table: [TableRow], root: URL, rules: GuardRules) -> (lines: [String], ok: Bool, extras: [Int], missing: [Int]) {
    guard let patterns = guardPatterns(root) else { return (["FAIL could not read KILLABLE_RE and PROTECT_RE from memory-guard.sh"], false, [], []) }
    let owners = CodingAgentHosts.sessionOwners(among: Dictionary(uniqueKeysWithValues: table.map { ($0.pid, (command: $0.args, ppid: $0.ppid)) }))
    let exempt = Set(owners.keys)
    let psLines = table.map { "\($0.pid) \($0.rssKB) \($0.args)" }.joined(separator: "\n") + "\n"
    let script = scriptCandidates(root: root, psLines: psLines, exempt: exempt, patterns: patterns)
    let groups = table.map { row in
        CensusGroup.fixture(name: row.args.split(separator: " ").first.map { ($0 as NSString).lastPathComponent } ?? "x", category: row.category,
                            members: [(row.pid, row.args.split(separator: " ").first.map { ($0 as NSString).lastPathComponent } ?? "x", row.args, Int64(row.rssKB) * 1024)],
                            lockedBy: owners[row.pid])
    }
    let engine = LegacyParity.engineCandidates(rules: rules, groups: groups, facts: RuleFacts()).map(\.pid)
    let sizes = Dictionary(uniqueKeysWithValues: table.map { ($0.pid, Int64($0.rssKB) * 1024) })
    let scriptSet = Set(script), engineSet = Set(engine)
    let extras = engineSet.subtracting(scriptSet).sorted(), missing = scriptSet.subtracting(engineSet).sorted()
    func label(_ pid: Int) -> String { "pid \(pid) \(table.first { $0.pid == pid }?.args.prefix(90) ?? "")" }
    var lines = ["the guard script may stop \(scriptSet.count): \(script.sorted())", "the engine would offer \(engineSet.count): \(engine.sorted())", "in both: \(scriptSet.intersection(engineSet).count)"]
    lines.append("only the script (the engine does not look there yet) \(missing.count):")
    lines += missing.map { "    \(label($0))" }
    lines.append("only the engine \(extras.count):")
    lines += extras.map { "    \(label($0))" }
    // what each does at the hard cap (6144 MB) and at critical pressure (500 MB): the same victim
    let capBytes = Int64(6144) * 1_048_576, criticalBytes = Int64(500) * 1_048_576
    let scriptPairs = script.map { (pid: $0, bytes: sizes[$0] ?? 0) }, enginePairs = engine.map { (pid: $0, bytes: sizes[$0] ?? 0) }
    let capScript = LegacyParity.victim(of: scriptPairs, over: capBytes), capEngine = LegacyParity.victim(of: enginePairs, over: capBytes)
    let criticalScript = LegacyParity.victim(of: scriptPairs, over: criticalBytes), criticalEngine = LegacyParity.victim(of: enginePairs, over: criticalBytes)
    lines.append("at the hard cap the script stops \(capScript.map(String.init) ?? "nothing"), the engine would offer \(capEngine.map(String.init) ?? "nothing")")
    lines.append("at critical pressure the script stops \(criticalScript.map(String.init) ?? "nothing"), the engine would offer \(criticalEngine.map(String.init) ?? "nothing")")
    let ok = extras.isEmpty && capScript == capEngine && criticalScript == criticalEngine
    return (lines, ok, extras, missing)
}

func probeCompareLegacy(_ args: [String]) -> Never {
    let root = useCheckout(args)
    // the plan that ships, with none of the person's own changes: the comparison is about the guard script's rule and the plan's
    GuardRules.use(directory: root.appending(path: "memory-analyzer/rules"), local: root.appending(path: "memory-analyzer/rules/no-local-changes.json"))
    let rules = GuardRules.load()
    var table = readTable(recordedTable)
    var heading = "recorded table (\(table.count) processes)"
    if args.contains("--real") {
        // this Mac's table, read only: every process with its command line, the category the census gives it
        table = MemoryCensus.realTable().map { TableRow(pid: $0.pid, ppid: $0.ppid, rssKB: $0.rssKB, category: $0.category, args: $0.command) }
        heading = "this Mac (\(table.count) processes, read only)"
    }
    print("comparing the guard script's choice with the engine's on the \(heading)")
    let result = compare(table, root: root, rules: rules)
    result.lines.forEach { print($0) }
    // the engine may leave a process the script would stop; it may never offer one the script would not
    print(result.ok ? "ok: the engine's set is inside the script's and both pick the same victim"
                    : "FAIL: the engine offers \(result.extras.count) the script would not, or a different victim")
    exit(result.ok ? 0 : 1)
}

// MARK: - --probe-rules-fixture

func probeRulesFixture(_ args: [String]) -> Never {
    let root = useCheckout(args)
    let rulesDir = root.appending(path: "memory-analyzer/rules")
    var failed = false
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("  \(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : ": \(detail)")")
        if !ok { failed = true }
    }
    let catalog = KindCatalog.current
    check("the kinds are usable", catalog.isAvailable, catalog.problems.joined(separator: "; "))
    guard catalog.isAvailable else { exit(1) }
    let scratch = ProbeScratch.folder("ma-probe-rules")
    func write(_ name: String, _ text: String) -> URL {
        let url = scratch.appending(path: name); try? text.write(to: url, atomically: true, encoding: .utf8); return url
    }

    // 1. the plan that ships
    GuardRules.use(directory: rulesDir, local: scratch.appending(path: "none.json"))
    let shipped = GuardRules.load()
    check("plan.json and protected.json read without a problem", shipped.problems.isEmpty, shipped.problems.joined(separator: "; "))
    check("six limits and eight steps, every one able to run",
          shipped.limits.count == 6 && shipped.steps.count == 8 && shipped.resolved.allSatisfy { if case .cantRun = $0.state { false } else { true } },
          "\(shipped.limits.count) limits, \(shipped.steps.count) steps")
    let acting = shipped.resolved.filter { $0.state == .acting }.map(\.id).sorted()
    check("only what the guard script already does is Acting (the dev-tooling cap and the critical-pressure stop), and each names its setting",
          acting == ["devTooling.limit", "step.devTooling.biggest"] && shipped.resolved.filter { $0.state == .acting }.allSatisfy { $0.rule.store != nil }, "\(acting)")
    check("everything new starts in Watching", shipped.resolved.filter { $0.state != .acting }.allSatisfy { $0.state == .watching })

    // 2. a plan with something wrong is not used in part, and one rule's problem is that rule's alone
    func plan(_ rules: String, header: String = "\"schema\": 1") -> GuardPlan {
        GuardPlan.parse(Data("{\(header), \"limits\": [\(rules)], \"whenMemoryRunsOut\": []}".utf8), catalog: catalog)
    }
    let good = "{\"id\":\"a\",\"kind\":\"tools.other\",\"gb\":6,\"measure\":\"unit\",\"overFor\":0,\"action\":\"notify\",\"mode\":\"watching\"}"
    let unknownField = "{\"id\":\"b\",\"kind\":\"tools.other\",\"gb\":6,\"measure\":\"unit\",\"overFor\":0,\"action\":\"notify\",\"mode\":\"watching\",\"surprise\":1}"
    let noKind = "{\"id\":\"c\",\"kind\":\"tools.nothing\",\"gb\":6,\"measure\":\"unit\",\"overFor\":0,\"action\":\"notify\",\"mode\":\"watching\"}"
    let badNumber = "{\"id\":\"d\",\"kind\":\"tools.other\",\"gb\":-1,\"measure\":\"unit\",\"overFor\":0,\"action\":\"notify\",\"mode\":\"watching\"}"
    let mixed = plan([good, unknownField, noKind, badNumber, good].joined(separator: ","))
    let verdicts = mixed.rules.map { $0.problem == nil }
    check("a rule with a field this version does not know, no kind, a bad number or a repeated id can't run; the good rule runs",
          verdicts == [true, false, false, false, false], "\(mixed.rules.map { $0.problem ?? "runs" })")
    check("a plan with an unknown top-level field has no rules at all", GuardPlan.parse(Data("{\"schema\":1,\"surprise\":2,\"limits\":[\(good)]}".utf8), catalog: catalog).rules.isEmpty)
    check("a plan of another schema has no rules at all", plan(good, header: "\"schema\": 2").rules.isEmpty)
    check("something that is not a plan has no rules and says so", GuardPlan.parse(Data("[]".utf8), catalog: catalog).problems.first == "not a JSON object")

    // 3. the person's own changes
    let planFile = write("plan.json", (try? String(contentsOf: rulesDir.appending(path: "plan.json"), encoding: .utf8)) ?? "")
    _ = planFile
    _ = write("protected.json", (try? String(contentsOf: rulesDir.appending(path: "protected.json"), encoding: .utf8)) ?? "")
    func load(local: String) -> GuardRules {
        let file = write("rules.local.json", local)
        GuardRules.use(directory: scratch, local: file)
        return GuardRules.load()
    }
    let changed = load(local: "{\"schema\":1,\"modes\":{\"apps.limit\":\"off\",\"macos.limit\":\"acting\",\"devTooling.limit\":\"acting\"},\"limits\":{\"simulators.limit\":{\"gb\":4,\"overFor\":30}},\"neverClose\":[\"Slack\"],\"mayQuit\":[\"Zoom\"]}")
    func state(_ id: String, _ rules: GuardRules) -> RuleState? { rules.resolved.first { $0.id == id }?.state }
    check("a rule the person turned off is Off", state("apps.limit", changed) == .off)
    check("Acting asked for a rule the script does not carry out stays Watching, and says why",
          state("macos.limit", changed) == .watching && changed.resolved.first { $0.id == "macos.limit" }?.note == Names.Guard.actingNotYet)
    check("Acting for the rule the script already carries out is Acting", state("devTooling.limit", changed) == .acting)
    if case .limit(let gb, _, let overFor, _)? = changed.resolved.first(where: { $0.id == "simulators.limit" })?.rule.shape {
        check("the person's limit and time replace the plan's", gb == 4 && overFor == 30, "\(gb) GB, \(overFor) s")
    } else { check("the person's limit and time replace the plan's", false) }
    check("the two lists are read", changed.local.neverClose == ["Slack"] && changed.local.mayQuit == ["Zoom"])
    let bad = load(local: "{\"schema\":1,\"modes\":{\"apps.limit\":\"off\"},\"surprise\":true}")
    check("a changes file with a field this version does not know is not used in part: the plan's defaults apply and it is reported",
          state("apps.limit", bad) == .watching && !bad.local.problems.isEmpty, "\(bad.local.problems)")
    check("a changes file that is not JSON is not used and is reported", !load(local: "not json").local.problems.isEmpty)

    // 4. what the rules do, on stand-in processes. Nothing is signalled: the evaluator only reads
    GuardRules.use(directory: rulesDir, local: scratch.appending(path: "none.json"))
    let rules = GuardRules.load()
    let GB: Int64 = 1_073_741_824
    func tool(_ name: String, _ command: String, gb: Double, pid: Int, kind: String? = nil, lockedBy: String? = nil, category: CensusGroup.Category = .tools) -> CensusGroup {
        CensusGroup.fixture(name: name, category: category, kind: kind, members: [(pid, name, command, Int64(gb * Double(GB)))], lockedBy: lockedBy)
    }
    let groups = [
        tool("shop-web", "node /Users/x/web/node_modules/.bin/vite", gb: 7, pid: 3000),                                   // dev tooling over the cap: the script's rule
        tool("iOS Simulator", "/Library/Developer/CoreSimulator/Volumes/x/launchd_sim", gb: 9, pid: 3100),                // Simulators & Emulators, over 8 GB
        tool("claude", "/Users/x/.local/bin/claude --resume", gb: 20, pid: 1000),                                         // a live coding session
        tool("BigApp", "/Applications/BigApp.app/Contents/MacOS/BigApp", gb: 13, pid: 3200, category: .apps),             // an app over 12 GB
        tool("FrontApp", "/Applications/FrontApp.app/Contents/MacOS/FrontApp", gb: 14, pid: 3300, category: .apps),        // ... in front
        tool("PerfPowerServices", "/usr/libexec/PerfPowerServicesSignpostReader", gb: 3, pid: 3400, category: .system),   // macOS, over 2 GB
        tool("postgres", "/opt/homebrew/opt/postgresql@16/bin/postgres -D /x", gb: 7, pid: 3500),                         // a database over 6 GB
        tool("report-export", "/usr/bin/python3 /Users/x/export.py", gb: 7, pid: 3600, lockedBy: "Codex"),               // ... a program a session started
    ]
    func kindOf(_ id: String) -> String { groups.first { $0.id.hasSuffix("/\(id.lowercased())") }?.kind.id ?? "?" }
    check("the stand-ins land in the kinds the rules target",
          kindOf("iOS Simulator") == "tools.simulators" && kindOf("claude") == "tools.codingAgents" && kindOf("postgres") == "tools.databases"
            && kindOf("PerfPowerServices") == "macos.services" && kindOf("BigApp") == "apps.other",
          "\(groups.map { "\($0.name)=\($0.kind.id)" })")

    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var state1 = RulesState()
    func facts(_ at: TimeInterval, pressure: LiveStats.Pressure = .normal, front: Set<String> = [], agents: Bool = true, paused: Bool = false) -> RuleFacts {
        RuleFacts(now: start.addingTimeInterval(at), pressure: pressure, frontApps: front, paused: paused, agentListAvailable: agents,
                  age: { _ in 3_600 }, start: { 1_799_990_000 + $0 })
    }
    func match(_ result: RuleEvaluation, _ rule: String, _ unit: String) -> RuleMatch? { result.matches.first { $0.rule.id == rule && $0.unit.name == unit } }
    func match(_ result: RuleEvaluation, _ rule: String, pid: Int) -> RuleMatch? { result.matches.first { $0.rule.id == rule && $0.unit.pid == pid } }
    var everyRow: [RuleOutcome] = []
    var first = RuleEvaluator.evaluate(rules: rules, groups: groups, facts: facts(0, front: ["frontapp"]), state: &state1)
    everyRow += first.outcomes
    check("developer tooling over the cap matches the rule the script carries out, and the engine writes NOTHING for it",
          match(first, "devTooling.limit", pid: 3000)?.status == .wouldAct && match(first, "devTooling.limit", pid: 3000)?.state == .acting
            && !first.outcomes.contains { $0.rule == "devTooling.limit" })
    check("a simulator over 8 GB would be stopped (Watching: one would-have row)", match(first, "simulators.limit", "iOS Simulator")?.status == .wouldAct
            && first.outcomes.filter { $0.rule == "simulators.limit" && $0.isWould }.count == 1)
    check("an app over its limit waits for the five minutes the rule gives it", {
        if case .waiting(let left)? = match(first, "apps.limit", "BigApp")?.status { return left == 300 }
        return false }(), "\(String(describing: match(first, "apps.limit", "BigApp")?.status))")
    check("the app in front is kept, and the row says so", {
        if case .kept(let why)? = match(first, "apps.limit", "FrontApp")?.status { return why.contains("in front") }
        return false }())
    check("a live coding session is never matched by a limit that stops", !first.matches.contains { $0.unit.name == "claude" && $0.state == .watching && $0.status == .wouldAct })
    check("a program a coding session started is kept", {
        if case .kept(let why)? = match(first, "commands.limit", "report-export")?.status { return why.contains("coding session") }
        return false }(), "\(String(describing: match(first, "commands.limit", "report-export")?.status))")
    check("every row written is Watching and nothing says it did anything", first.outcomes.allSatisfy { $0.mode == "watching" && ($0.result == "would" || $0.result == "kept") })
    check("a unit is written once a day: the same look again writes nothing new",
          RuleEvaluator.evaluate(rules: rules, groups: groups, facts: facts(10, front: ["frontapp"]), state: &state1).outcomes.isEmpty)
    first = RuleEvaluator.evaluate(rules: rules, groups: groups, facts: facts(301, front: ["frontapp"]), state: &state1)
    everyRow += first.outcomes
    check("after the five minutes the app would have been asked, once", match(first, "apps.limit", "BigApp")?.status == .wouldAct
            && first.outcomes.filter { $0.rule == "apps.limit" && $0.name == "BigApp" }.count == 1)
    check("the database, which waits the same five minutes, would be told about", {
        let row = first.outcomes.first { $0.rule == "databases.limit" }
        return row?.action == "notify" && row?.name == "postgres" }())
    check("a macOS process over its limit is told about (a notification), not stopped", {
        let later = RuleEvaluator.evaluate(rules: rules, groups: groups, facts: facts(700, front: ["frontapp"]), state: &state1)
        everyRow += later.outcomes
        let row = later.outcomes.first { $0.rule == "macos.limit" }
        return row?.action == "notify" && row?.category == "system" }())

    // the ladder, when memory has run out
    var state2 = RulesState()
    let calm = RuleEvaluator.evaluate(rules: rules, groups: groups, facts: facts(0), state: &state2)
    check("at normal pressure the ladder is shown as what it would pick and nothing from it is written",
          calm.picks.count == 8 && !calm.outcomes.contains { $0.rule.hasPrefix("step.") })
    check("the step that needs to know what is idle says it cannot be judged yet", calm.picks.first { $0.rule.id == "step.devTooling.idle" }?.note != nil)
    let devPick = calm.picks.first { $0.rule.id == "step.devTooling.biggest" }
    check("the script's critical-pressure step names the biggest developer process over 500 MB", devPick?.match?.unit.pid == 3000 && devPick?.state == .acting)
    let critical = RuleEvaluator.evaluate(rules: rules, groups: groups, facts: facts(0, pressure: .critical), state: &state2)
    let stepRows = critical.outcomes.filter { $0.rule.hasPrefix("step.") }
    check("with memory run out the first Watching step that has something to pick is written, one row", stepRows.count == 1,
          "\(stepRows.map { "\($0.rule) \($0.name)" })")
    check("an empty list of apps that may be asked to quit picks nothing", critical.picks.first { $0.rule.id == "step.apps.listed" }?.match == nil)
    let listed = RuleEvaluator.evaluate(rules: GuardRules(plan: rules.plan, local: GuardLocalRules(mayQuit: ["BigApp"]), protected: rules.protected, catalog: catalog),
                                        groups: groups, facts: facts(0, pressure: .critical, front: ["frontapp"]), state: &state2)
    check("an app the person put on the list would be asked to quit", listed.picks.first { $0.rule.id == "step.apps.listed" }?.match?.unit.name == "BigApp")

    // protections the rules cannot remove
    var state3 = RulesState()
    let blind = RuleEvaluator.evaluate(rules: rules, groups: groups, facts: facts(0, agents: false), state: &state3)
    check("when the list of coding agents cannot be read nothing in Tools is judged safe", {
        if case .kept(let why)? = match(blind, "simulators.limit", "iOS Simulator")?.status { return why == CodingAgentHosts.unavailableSentence }
        return false }())
    let never = RuleEvaluator.evaluate(rules: GuardRules(plan: rules.plan, local: GuardLocalRules(neverClose: ["iOS Simulator"]), protected: rules.protected, catalog: catalog),
                                       groups: groups, facts: facts(0), state: &state3)
    check("a program on the person's Never Close list is kept", {
        if case .kept(let why)? = match(never, "simulators.limit", "iOS Simulator")?.status { return why.contains("never be closed") }
        return false }())
    check("a paused guard evaluates nothing", RuleEvaluator.evaluate(rules: rules, groups: groups, facts: facts(0, paused: true), state: &state3).skipped != nil)
    let young = RuleEvaluator.evaluate(rules: rules, groups: groups, facts: RuleFacts(now: start, age: { _ in 5 }, start: { _ in 1 }), state: &state3)
    check("a process that has just started is not acted on (60 seconds for what is new, none for developer tooling)",
          match(young, "simulators.limit", "iOS Simulator")?.status == .tooNew && match(young, "devTooling.limit", pid: 3000)?.status == .wouldAct)

    // 5. the log of would-have rows
    let log = scratch.appending(path: "rule-outcomes.jsonl")
    everyRow += critical.outcomes
    RuleOutcomes.append(everyRow, to: log)
    if let handle = try? FileHandle(forWritingTo: log) { _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data("{\"ref\":\"half".utf8)); try? handle.close() }
    let back = RuleOutcomes.read(since: start.addingTimeInterval(-1), from: log)
    check("the rows come back, newest first, and a half-written last line is left out", back.count == everyRow.count && !everyRow.isEmpty
            && zip(back, back.dropFirst()).allSatisfy { $0.time >= $1.time }, "\(back.count) rows")
    check("the rows older than the period asked for are left out", RuleOutcomes.read(since: start.addingTimeInterval(10_000), from: log).isEmpty)
    check("a rule's would-have and kept rows are counted apart", RuleOutcomes.counts(back, rule: "apps.limit").would == 1 && RuleOutcomes.counts(back, rule: "apps.limit").kept == 1,
          "\(RuleOutcomes.counts(back, rule: "apps.limit"))")

    // the panel's lines: one per category with something today, in words that say what WOULD have happened
    let lines = RuleOutcomes.todayLines(back)
    check("the panel gets a line for Apps, Tools and macOS that have something, in that order, each opening its own tab",
          lines.map(\.category) == [.apps, .tools, .system] && lines.map(\.target) == ["guard:apps", "guard:tools", "guard:macos"],
          "\(lines.map(\.text))")
    check("a line says what would have happened and never that it did", lines.allSatisfy { $0.text.contains("would have") || $0.text.contains("to know about") }
            && !lines.contains { $0.text.contains(" stopped ") && !$0.text.contains("would have stopped") }, "\(lines.map(\.text))")
    check("a day with nothing has no lines", RuleOutcomes.todayLines([]).isEmpty)

    // 6. what the guard script reads
    let text = GuardFallbackFile.contents(hardCapMB: 8192, hardCapStop: true, pressureStop: false,
                                          neverClosePaths: ["/Users/x/bin/a.b[1](x)+", "relative/path", "/Users/x/tab\tname", "/Users/x/ok"])
    check("the fallback file holds the numbers, the pause line and only the full paths that are safe to write",
          text == "hardCapMB\t8192\nhardCapStop\t1\npressureStop\t0\nneverClosePath\t/Users/x/bin/a.b[1](x)+\nneverClosePath\t/Users/x/ok\npause\t0\n", text.replacingOccurrences(of: "\t", with: "<TAB>"))

    // 7. the guard script's choice against the engine's, on a recorded table
    let comparison = compare(readTable(recordedTable), root: root, rules: rules)
    check("on the recorded table the engine offers nothing the script would not, and both pick the same victim", comparison.ok, comparison.lines.suffix(6).joined(separator: " | "))
    check("the script alone may stop dev tooling inside an app bundle and a program named with 'vite' in it: the two listed differences",
          comparison.missing == [3007, 3008], "\(comparison.missing)")
    check("a live coding session and everything below it is in neither set", ![1000, 1001, 1002, 3009, 3010].contains { comparison.missing.contains($0) || comparison.extras.contains($0) })

    print(failed ? "FAIL" : "ok")
    exit(failed ? 1 : 0)
}
