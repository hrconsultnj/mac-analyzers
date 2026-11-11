import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-panel-stop` proves what the menu-bar panel's Quit and Stop do, with throwaway
// processes this probe starts and ends itself, in a throwaway home (`ProbeSandbox`), with a fake list of
// coding agents that names one fixture program a "session".
//
// The panel's whole decision is `PanelStop` (the same code the panel runs): it asks `MemoryStop` for a plan
// from the live process table, shows a refusal as a sentence, confirms a plan with the plan's own words, and
// never forces. These cases hold it to that, and the probe exits non-zero when one fails.

@MainActor func probePanelStop(_ args: [String]) async -> Never {
    if !args.contains("--detached-child") { relaunchDetached(args) }
    let root = probeRoot(args)
    guard let realList = try? String(contentsOf: root.appending(path: "lib/coding-agents.tsv"), encoding: .utf8),
          realList.contains("\texe\tclaude") else {
        print("the coding-agent list was not found under \(root.path) (pass --root <checkout>): the panel's Stop was NOT judged")
        exit(2)
    }
    guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/bash") else {
        print("no shell outside the system folders to use as a fixture: the panel's Stop was NOT judged")
        exit(2)
    }
    let f = Fixtures(shell: "/opt/homebrew/bin/bash")
    let list = f.scratch.appending(path: "agents.tsv")
    try? (realList + "\nFixture Agent\texe\t\(f.sessionExe)\n-\tcontainer\t\(f.appName)\n").write(to: list, atomically: true, encoding: .utf8)
    CodingAgentHosts.useList(at: list)
    print("the panel's Quit and Stop, with throwaway processes (all started and ended here):")

    /// The fixture's group narrowed to the fixture's own program: the census groups every `bash` together
    /// (what a row would be), and a row whose group holds one program is exactly this.
    func group(of pid: Int32) -> CensusGroup? {
        guard let whole = MemoryCensus.take().groups.first(where: { $0.members.contains { $0.pid == Int(pid) } }),
              let program = whole.programs.first(where: { $0.members.contains { $0.pid == Int(pid) } }) else { return nil }
        return whole.keeping(program.members)
    }
    /// The group is the fixture and what it started, nothing of the person's.
    func contained(_ g: CensusGroup, _ pid: Int32) -> Bool {
        let allowed = Set([pid] + ProcessTree.descendants(of: pid))
        return g.members.allSatisfy { allowed.contains(Int32($0.pid)) }
    }

    // 1. a Stop on a plain tool: planned, nothing sent until confirmed, then exactly that process ends
    let bystander = await f.detachNamed("\(f.marker)-bystander", script: ": \(f.marker)-by; sleep 90; :", tag: "\(f.marker)-by")
    if let tool = await f.detachNamed("\(f.marker)-tool", script: ": \(f.marker)-t; sleep 90; :", tag: "\(f.marker)-t") {
        if let g = group(of: tool), contained(g, tool) {
            f.check("a plain tool offers Stop", PanelStop.offer(for: g) == .stop, "\(PanelStop.offer(for: g))")
            if case .ask(let plan) = PanelStop.begin(group: g) {
                f.check("the plan says what it will do, in its own words", plan.title.hasPrefix("Stop ") && plan.actionTitle.hasPrefix("Stop "),
                        "\(plan.title) / \(plan.actionTitle)")
                try? await Task.sleep(for: .seconds(1))     // long enough for anything started behind the plan's back
                f.check("nothing is sent until it is confirmed", f.alive(tool) && (bystander.map(f.alive) ?? false), "still running a second later: \(f.alive(tool))")
                let done = await PanelStop.confirm(plan, group: g.name)
                f.check("confirmed, it ends exactly that process", f.gone(tool) && (bystander.map(f.alive) ?? false),
                        "tool gone: \(f.gone(tool)), bystander alive: \(bystander.map(f.alive) ?? false), said: \(done.message ?? "stopped")")
            } else { f.check("a plain tool's Stop is planned for confirmation", false, "no plan") }
        } else { f.check("a plain tool offers Stop", false, "group not found or not contained: refusing to signal") }
        f.end(tool)
    } else { f.check("a plain tool offers Stop", false, "fixture not found") }
    if let bystander { f.end(bystander) }

    // 2. a Stop on a coding session's own process is refused: nothing is signalled
    if let session = await f.detachNamed(f.sessionExe, script: ": \(f.marker)-s; sleep 90; :", tag: "\(f.marker)-s") {
        if let g = group(of: session), contained(g, session) {
            var reason = ""
            if case .locked(let why) = PanelStop.offer(for: g) { reason = why }
            f.check("a session's own process shows no Stop, with the sentence", reason.contains("live Fixture Agent"), reason.isEmpty ? "offered" : reason)
            var said = ""
            if case .say(let why) = PanelStop.begin(group: g) { said = why }
            f.check("pressing anyway is refused in the same words, and nothing is signalled", said == reason && !said.isEmpty && f.alive(session),
                    "\(said) — still running: \(f.alive(session))")
        } else { f.check("a session's own process shows no Stop", false, "group not found or not contained: refusing to signal") }
        f.end(session)
    } else { f.check("a session's own process shows no Stop", false, "fixture not found") }

    // 3. a Quit on an app that hosts a session: the warning, and nothing is sent until confirmed
    if let host = await f.detachNamed(f.appName, script: ": \(f.marker)-h; ( exec -a \(f.sessionExe) \(f.shell) -c \": \(f.marker)-h2; sleep 90; :\" ) & wait; :", tag: "\(f.marker)-h"),
       let identity = ProcessIdentity.of(pid: Int(host)),
       let g = CensusGroup.standInApp(name: f.appName, root: identity) {
        f.check("an app offers Quit", PanelStop.offer(for: g) == .quit, "\(PanelStop.offer(for: g))")
        if case .ask(let plan) = PanelStop.begin(group: g) {
            f.check("the Quit warns that the session inside will end, and that containers stop",
                    plan.detail.contains("live Fixture Agent session") && plan.detail.contains("Containers running in it will stop"), plan.detail)
            f.check("its title and action word come from the plan", plan.title == "Quit \(f.appName)?" && plan.actionTitle == "Quit \(f.appName)",
                    "\(plan.title) / \(plan.actionTitle)")
            try? await Task.sleep(for: .seconds(1))
            f.check("nothing is sent until it is confirmed", f.alive(host), "still running a second later: \(f.alive(host))")
            let done = await PanelStop.confirm(plan, group: g.name)
            f.check("confirmed, an app-less process hosting a session is still not ended by the panel", f.alive(host),
                    done.message ?? "no message")
        } else { f.check("an app's Quit is planned for confirmation", false, "no plan") }
        f.end(host)
    } else { f.check("an app offers Quit", false, "fixture not found") }

    // 4. a program that ignores the polite stop is not forced: the panel offers Monitor instead
    if let stubborn = await f.detachNamed("\(f.marker)-stubborn", script: ": \(f.marker)-x; trap \"\" TERM; sleep 91 & wait; :", tag: "\(f.marker)-x") {
        if let g = group(of: stubborn), contained(g, stubborn), case .ask(let plan) = PanelStop.begin(group: g) {
            let done = await PanelStop.confirm(plan, group: g.name)
            f.check("after a polite stop that did not work, nothing is forced", f.alive(stubborn), "still running: \(f.alive(stubborn))")
            f.check("the panel offers Monitor on that program, where Force Stop lives",
                    done.monitorLink == MemoryStop.monitorLink(forGroup: g.name), done.monitorLink ?? "no link")
        } else { f.check("a stubborn program's polite stop is planned", false, "group not found, not contained or not planned") }
        f.end(stubborn)
    } else { f.check("a stubborn program's polite stop is planned", false, "fixture not found") }

    // 5. without the list of coding agents no Stop is offered at all, and pressing is refused
    if let tool = await f.detachNamed("\(f.marker)-tool2", script: ": \(f.marker)-t2; sleep 90; :", tag: "\(f.marker)-t2") {
        let missing = f.scratch.appending(path: "not-there.tsv")
        CodingAgentHosts.useList(at: missing)
        if let g = group(of: tool), contained(g, tool) {
            var offered = ""
            if case .locked(let why) = PanelStop.offer(for: g) { offered = why }
            var said = ""
            if case .say(let why) = PanelStop.begin(group: g) { said = why }
            f.check("with the list missing there is no Stop, and pressing is refused with the same sentence",
                    offered == CodingAgentHosts.unavailableSentence && said == CodingAgentHosts.unavailableSentence && f.alive(tool),
                    offered.isEmpty ? "offered" : offered)
        } else { f.check("with the list missing there is no Stop", false, "group not found or not contained") }
        CodingAgentHosts.useList(at: list)
        f.end(tool)
    } else { f.check("with the list missing there is no Stop", false, "fixture not found") }

    f.cleanup()
    print(f.failed ? "the panel's Quit and Stop FAILED a case" : "all cases passed")
    exit(f.failed ? 1 : 0)
}
