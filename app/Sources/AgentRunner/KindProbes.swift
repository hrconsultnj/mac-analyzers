import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-kinds [--all]` prints every running group with its category, its kind, the rule that
// decided it (and whether that rests on an identity or only on a name) and what Memory Guard may do to it, then
// compares the kinds with the pattern the guard script still uses (`KILLABLE_RE` in memory-guard.sh): the set
// the pattern selects against the set of developer-tooling kinds, on this Mac's process table, with the
// difference. It reads this Mac and exits 0 unless the catalog or a category is broken.
//
// `agent-runner --probe-kinds-fixture` judges the same rules on a table it writes itself, so the answer never
// depends on what runs here, and exits non-zero when a rule breaks: a process in the wrong kind or category, a
// kind no row reaches, a broken catalog accepted, or a difference from the pattern that is not the one listed.
// `scripts/check.sh probes` runs it.

/// The pattern the guard script uses, read from the script itself: the only copy there is.
private func guardPattern(_ root: URL) -> NSRegularExpression? {
    let script = root.appending(path: "memory-analyzer/memory-guard.sh")
    guard let text = try? String(contentsOf: script, encoding: .utf8),
          let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("KILLABLE_RE='") }) else { return nil }
    let pattern = line.dropFirst("KILLABLE_RE='".count).dropLast()
    return try? NSRegularExpression(pattern: String(pattern))
}

private func selects(_ pattern: NSRegularExpression, _ text: String) -> Bool {
    pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

private func useCheckout(_ args: [String]) -> URL {
    let root = probeRoot(args)
    KindCatalog.use(file: root.appending(path: "memory-analyzer/rules/kinds.json"))
    CodingAgentHosts.useList(at: root.appending(path: "lib/coding-agents.tsv"))
    return root
}

private func line(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width - 1)) + " " : text + String(repeating: " ", count: width - text.count)
}

// MARK: - this Mac

func probeKinds(_ args: [String]) -> Never {
    let root = useCheckout(args)
    let catalog = KindCatalog.current
    guard catalog.isAvailable else {
        print("FAIL kinds.json is not usable: \(catalog.problems.joined(separator: "; "))")
        exit(1)
    }
    guard let pattern = guardPattern(root) else {
        print("FAIL could not read KILLABLE_RE from memory-analyzer/memory-guard.sh")
        exit(1)
    }
    var failed = false
    let census = MemoryCensus.take()
    var byKind: [String: (count: Int, bytes: Int64)] = [:]
    for group in census.groups {
        var entry = byKind[group.kind.id] ?? (0, 0)
        entry.count += 1
        entry.bytes += group.totalBytes
        byKind[group.kind.id] = entry
        if group.kind.category != group.category {
            print("FAIL \(group.name): kind \(group.kind.id) is in \(group.kind.category.rawValue), the group in \(group.category.rawValue)")
            failed = true
        }
        if group.kindMatch.basis == .name, catalog.nameOnlyReason(of: group.kind) == nil {
            print("FAIL \(group.name): decided by a name and \(group.kind.id) says no why")
            failed = true
        }
    }

    print("kinds on this Mac (\(census.groups.count) groups, catalog: \(catalog.source?.path ?? "?")):")
    for kind in catalog.kinds {
        let found = byKind[kind.id]
        print("  \(line(kind.category.rawValue, 7))\(line(kind.name, 28))\(line("\(found?.count ?? 0) groups", 12))\(MemorySize.text(found?.bytes ?? 0))"
              + (kind.devTooling ? "  [developer tooling]" : ""))
    }

    for category in CensusGroup.Category.allCases {
        let groups = census.groups(in: category)
        print("\n\(category.title) · \(groups.count) groups")
        print("  " + line("GROUP", 34) + line("KIND", 26) + line("DECIDED BY", 40) + "CATALOG POLICY (the guard script does not read it yet)")
        let shown = args.contains("--all") ? groups : Array(groups.prefix(25))
        for group in shown {
            let match = group.kindMatch
            let basis = match.basis == .identity ? "" : " (\(match.basis.rawValue))"
            print("  " + line(group.name, 34) + line(group.kind.name, 26) + line(match.rule + basis, 40) + group.kind.guardMay)
            if let reason = group.leftAlone { print("  " + String(repeating: " ", count: 34) + "left alone: \(reason)") }
        }
        if shown.count < groups.count { print("  … \(groups.count - shown.count) more (--all lists them)") }
    }

    // migration parity: the guard script's pattern against the developer-tooling kinds, on the commands the census reads
    let table = MemoryCensus.kindRows()
    var both: [String] = [], onlyPattern: [String] = [], onlyKinds: [String] = []
    for row in table.rows {
        let old = selects(pattern, row.command)
        let new = catalog.isDevTooling(row.subject, environment: table.environment)
        let label = "pid \(row.pid)  \(row.command.prefix(110))"
        if old && new { both.append(label) } else if old { onlyPattern.append(label) } else if new { onlyKinds.append(label) }
    }
    print("\nmigration parity on \(table.rows.count) commands: pattern selects \(both.count + onlyPattern.count), "
          + "developer-tooling kinds select \(both.count + onlyKinds.count), both \(both.count)")
    print("  selected by the pattern only (\(onlyPattern.count)):")
    for item in onlyPattern.prefix(30) { print("    \(item)") }
    print("  selected by the kinds only (\(onlyKinds.count)):")
    for item in onlyKinds.prefix(30) { print("    \(item)") }
    print(failed ? "FAIL" : "ok: every group has a kind of its own category")
    exit(failed ? 1 : 0)
}

// MARK: - the fixture

private struct Row {
    let label: String
    let category: CensusGroup.Category
    let subject: ProcessSubject
    let kind: String
    let basis: KindMatch.Basis
    /// The pattern and the kinds are expected to disagree here, and why. nil: they must agree.
    var difference: (patternSelects: Bool, why: String)?
}

func probeKindsFixture(_ args: [String]) -> Never {
    let root = useCheckout(args)
    var failed = false
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("  \(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : ": \(detail)")")
        if !ok { failed = true }
    }

    let catalog = KindCatalog.current
    check("kinds.json reads and passes its own rules", catalog.isAvailable, catalog.problems.joined(separator: "; "))
    guard catalog.isAvailable, let pattern = guardPattern(root) else {
        check("the guard script's pattern is readable", false)
        exit(1)
    }
    check("every kind has a name", catalog.kinds.allSatisfy { Names.Kind.name(forID: $0.id) != nil })

    // rules the catalog must refuse: a broken file is never used in part
    func bad(_ edit: (inout [String: Any]) -> Void, _ name: String) {
        guard let data = try? Data(contentsOf: root.appending(path: "memory-analyzer/rules/kinds.json")),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            check(name, false, "cannot read the file"); return
        }
        edit(&object)
        let broken = (try? JSONSerialization.data(withJSONObject: object)).map { KindCatalog.parse($0) }
        check(name, broken?.isAvailable == false, broken?.problems.first ?? "accepted")
    }
    bad({ $0["surprise"] = 1 }, "a field the catalog does not know is refused")
    bad({ object in
        var kinds = object["kinds"] as? [[String: Any]] ?? []
        kinds.removeAll { ($0["fallback"] as? Bool) == true && ($0["id"] as? String) == "tools.other" }
        object["kinds"] = kinds
    }, "a category without a fallback kind is refused")
    bad({ object in
        var kinds = object["kinds"] as? [[String: Any]] ?? []
        if let at = kinds.firstIndex(where: { ($0["id"] as? String) == "tools.toolServers" }) { kinds[at]["nameOnlyBecause"] = nil }
        object["kinds"] = kinds
    }, "a rule that goes by a name without saying why is refused")
    bad({ object in
        var kinds = object["kinds"] as? [[String: Any]] ?? []
        if let at = kinds.firstIndex(where: { ($0["id"] as? String) == "tools.runtimes" }) {
            var rules = kinds[at]["recognizedBy"] as? [[String: Any]] ?? []
            if !rules.isEmpty { rules[0]["basis"] = "name" }
            kinds[at]["recognizedBy"] = rules
        }
        object["kinds"] = kinds
    }, "a rule that claims an identity it does not have is refused")

    let me: UInt32 = 501
    let environment = KindEnvironment(httpsHandlers: ["com.operasoftware.opera", "com.googlecode.iterm2"],
                                      launchdJobs: [700: "com.example.syncer", 710: "com.example.refresh"])
    func tool(_ label: String, _ command: String, _ kind: String, _ basis: KindMatch.Basis = .identity,
              path: String? = nil, pid: Int = 9000, ppid: Int = 600, uid: UInt32 = 501, difference: (Bool, String)? = nil) -> Row {
        let first = command.split(separator: " ").first.map(String.init) ?? command
        return Row(label: label, category: .tools,
                   subject: ProcessSubject(path: path ?? first, command: command, uid: uid, me: me, ppid: ppid, pid: pid),
                   kind: kind, basis: basis, difference: difference.map { ($0.0, $0.1) })
    }
    func app(_ label: String, _ name: String, _ bundleID: String, _ kind: String, _ basis: KindMatch.Basis = .identity,
             appCategory: String? = nil) -> Row {
        let path = "/Applications/\(name).app"
        return Row(label: label, category: .apps,
                   subject: ProcessSubject(path: "\(path)/Contents/MacOS/\(name)", uid: 501, me: me, bundleID: bundleID,
                                           appCategory: appCategory, appName: name, appPath: path),
                   kind: kind, basis: basis)
    }
    func system(_ label: String, _ path: String, uid: UInt32, _ kind: String) -> Row {
        Row(label: label, category: .system, subject: ProcessSubject(path: path, uid: uid, me: me, ppid: 1),
            kind: kind, basis: kind == "macos.system" ? .identity : .fallback)
    }

    let rows: [Row] = [
        // apps: bundle identifiers, the web-link handlers, the app category, the shared container list
        app("Opera opens web links", "Opera", "com.operasoftware.Opera", "apps.browsers"),
        app("iTerm opens web links but is a terminal", "iTerm", "com.googlecode.iterm2", "apps.terminals"),
        app("Zoom", "zoom.us", "us.zoom.xos", "apps.meeting"),
        app("Teams (new)", "Microsoft Teams", "com.microsoft.teams2", "apps.meeting"),
        app("VS Code", "Visual Studio Code", "com.microsoft.VSCode", "apps.editors"),
        app("an editor by its app category", "Antigravity", "com.example.agy", "apps.editors", appCategory: "public.app-category.developer-tools"),
        app("OrbStack, by identifier, ahead of its app category", "OrbStack", "dev.kdrag0n.MacVirt", "apps.containers",
            appCategory: "public.app-category.developer-tools"),
        app("a container app known only by name", "Rancher Desktop", "io.example.rancher", "apps.containers", .name),
        app("Tailscale's app and its helper identifiers", "Tailscale", "io.tailscale.ipn.macsys", "apps.connection"),
        app("any other app", "Weather Stand-In", "com.example.weather", "apps.other", .fallback),
        // tools: sessions, connection, services, databases, simulators
        tool("a coding session", "/Users/x/.local/bin/claude --resume", "tools.codingAgents"),
        tool("a mesh VPN daemon", "/usr/local/bin/tailscaled --state=/x", "tools.connection"),
        tool("launchd keeps it running: the very process it runs for the job", "/Users/x/bin/syncer --watch", "tools.backgroundServices",
             path: "/Users/x/bin/syncer", pid: 700, ppid: 1),
        tool("a job that runs node is that one process", "/Users/x/.nvm/bin/node /Users/x/refresh.js", "tools.backgroundServices",
             path: "/Users/x/.nvm/bin/node", pid: 710, ppid: 1,
             difference: (true, "the pattern selects node; the kind is a background service launchd restarts, which is not developer tooling")),
        tool("an orphan of the interpreter a job runs is not that job", "/Users/x/.nvm/bin/node /Users/x/p/server.js", "tools.runtimes",
             path: "/Users/x/.nvm/bin/node", pid: 711, ppid: 1),
        tool("the same program started by hand", "/Users/x/bin/syncer --watch", "tools.other", .fallback, path: "/Users/x/bin/syncer"),
        tool("PostgreSQL", "/opt/homebrew/opt/postgresql@16/bin/postgres -D /x", "tools.databases"),
        tool("Redis, named by its first word", "redis-server *:6379", "tools.databases", path: "/opt/homebrew/bin/redis-server"),
        tool("an iOS simulator's launchd", "/Library/Developer/CoreSimulator/Volumes/x/launchd_sim /x", "tools.simulators"),
        tool("an Android emulator", "/x/emulator/qemu-system-aarch64 -M virt", "tools.simulators"),
        // tools: developer tooling, the families the guard's pattern selects
        tool("a Vite server", "/usr/local/bin/node /Users/x/p/node_modules/.bin/vite", "tools.devServers", path: "/usr/local/bin/node"),
        tool("a Next.js server by its title", "next-server (v14.2.0)", "tools.devServers", path: "/usr/local/bin/node"),
        tool("next dev, by its words", "/usr/local/bin/node /Users/x/p/node_modules/.bin/next dev", "tools.devServers", .name,
             path: "/usr/local/bin/node"),
        tool("Turborepo", "/Users/x/p/node_modules/turbo-darwin-arm64/bin/turbo run dev", "tools.buildDaemons"),
        tool("webpack", "/usr/local/bin/node /Users/x/p/node_modules/webpack/bin/webpack.js", "tools.buildDaemons", path: "/usr/local/bin/node"),
        tool("esbuild", "/Users/x/p/node_modules/@esbuild/darwin-arm64/bin/esbuild --service=0.20", "tools.buildDaemons"),
        tool("tsup", "/usr/local/bin/node /Users/x/p/node_modules/.bin/tsup --watch", "tools.buildDaemons", path: "/usr/local/bin/node"),
        tool("Jest", "/usr/local/bin/node /Users/x/p/node_modules/.bin/jest --watch", "tools.testRunners", path: "/usr/local/bin/node"),
        tool("a Jest worker", "/usr/local/bin/node /Users/x/p/node_modules/jest-worker/build/workers/processChild.js", "tools.testRunners", .name,
             path: "/usr/local/bin/node"),
        tool("Vitest", "/usr/local/bin/node /Users/x/p/node_modules/vitest/vitest.mjs", "tools.testRunners", path: "/usr/local/bin/node"),
        tool("Playwright's browser, by its folder", "/Users/x/Library/Caches/ms-playwright/chromium-1/chrome-mac/Chromium --foo", "tools.testBrowsers"),
        tool("headless_shell", "/x/headless_shell --no-sandbox", "tools.testBrowsers"),
        tool("a headless browser, by its flag", "/Users/x/bin/chrome --headless=new --foo", "tools.testBrowsers", .name),
        tool("an MCP server run by npx reads as its runtime", "/usr/local/bin/npx -y @modelcontextprotocol/server-memory", "tools.runtimes", path: "/usr/local/bin/npx"),
        tool("an MCP server run by node reads as its runtime", "/usr/local/bin/node /Users/x/mcp-server-files/index.js", "tools.runtimes", path: "/usr/local/bin/node"),
        tool("an MCP server that is not a Node program", "/Users/x/bin/files-mcp-server --stdio", "tools.toolServers", .name),
        tool("node", "/opt/homebrew/bin/node /Users/x/app/server.js", "tools.runtimes", path: "/opt/homebrew/bin/node"),
        tool("npm", "npm run dev", "tools.runtimes", path: "/usr/local/bin/npm"),
        tool("bun", "/opt/homebrew/bin/bun run dev", "tools.runtimes"),
        tool("deno", "/opt/homebrew/bin/deno run x.ts", "tools.runtimes"),
        tool("tsx", "/usr/local/bin/tsx watch x.ts", "tools.runtimes"),
        // tools: what the pattern never selects
        tool("Python", "/usr/bin/python3 /Users/x/app.py", "tools.other", .fallback),
        tool("a shell", "/bin/zsh -l", "tools.other", .fallback),
        tool("ssh", "/usr/bin/ssh host", "tools.other", .fallback),
        tool("a program whose name starts with node", "/Users/x/node-notes/run.sh", "tools.other", .fallback),
        // tools: where the pattern and the kinds are meant to disagree
        tool("a coding agent's runtime started with --headless", "/x/copilot-runtime --headless --stdio", "tools.codingAgents",
             difference: (true, "the pattern matches --headless; the kind is a live coding session, which the guard never touches")),
        tool("a name that only contains \"vite\"", "/Users/x/bin/invite-cleanup --all", "tools.other", .fallback,
             difference: (true, "the pattern matches the text \"vite\" inside \"invite\"; the kinds go by the program's identity")),
        // macOS
        system("a process of the system account", "/usr/libexec/PerfPowerServicesSignpostReader", uid: 0, "macos.system"),
        system("a macOS service of this account", "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock", uid: 501, "macos.services"),
    ]

    print("rules on \(rows.count) stand-in processes:")
    var reached = Set<String>()
    for row in rows {
        let match = catalog.recognize(row.subject, in: row.category, environment: environment)
        reached.insert(match.kind.id)
        let ok = match.kind.id == row.kind && match.basis == row.basis && match.kind.category == row.category
        check(row.label, ok, ok ? "\(match.kind.id) by \(match.rule)"
              : "wanted \(row.kind) (\(row.basis.rawValue)), got \(match.kind.id) (\(match.basis.rawValue)) by \(match.rule)")
    }
    let unreached = catalog.kinds.map(\.id).filter { !reached.contains($0) }
    check("every kind is reached by a row", unreached.isEmpty, unreached.joined(separator: ", "))

    // migration parity: the guard script's pattern against developer-tooling kinds, process by process
    var both = 0, expectedDifferences = 0
    for row in rows where row.category == .tools {
        let old = selects(pattern, row.subject.command)
        let new = catalog.isDevTooling(row.subject, environment: environment)
        if old == new {
            both += 1
            check("parity: \(row.label)", row.difference == nil, row.difference == nil ? (old ? "both select" : "neither selects") : "listed as a difference but they agree")
        } else {
            expectedDifferences += 1
            let listed = row.difference.map { $0.patternSelects == old } == true
            check("difference: \(row.label)", listed, listed ? "pattern \(old ? "selects" : "does not"), kinds \(new ? "do" : "do not") — \(row.difference?.why ?? "")"
                  : "an unlisted difference")
        }
    }
    print("parity: \(both) processes agree, \(expectedDifferences) listed differences")
    check("the pattern selects something (the oracle is real)", rows.contains { selects(pattern, $0.subject.command) })

    // a broken catalog reads every process as unclassified, which allows nothing
    let none = KindCatalog.parse(Data("{}".utf8))
    let unclassified = none.recognize(ProcessSubject(path: "/x/node", uid: me, me: me), in: .tools)
    check("an unusable catalog allows the guard nothing", unclassified.kind.stopsWith == .none && !unclassified.kind.devTooling)

    print(failed ? "FAIL" : "ok")
    exit(failed ? 1 : 0)
}
