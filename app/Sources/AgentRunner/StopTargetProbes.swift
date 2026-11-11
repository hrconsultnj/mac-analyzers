import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-stop-targets --root <checkout>` prints what a group Stop would
// offer, then proves what ONE Stop can and cannot reach, using throwaway processes this
// probe starts and ends itself.
//
// Every fixture is started DETACHED (its parent is launchd), from a shell outside the
// system folders (the census calls /bin/bash part of macOS). Started as a child of this
// probe, a fixture would be one program with the probe, the shell that ran it and the
// coding session above it. Each fixture carries a unique marker in its command line, and
// the probe signals nothing unless every member of the program it is about to stop is the
// fixture or under it. A fake coding-agent list (the real one plus one line naming a
// fixture program) stands in for "a session", so no real session is ever involved.

private func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width - 1)) + " " : text + String(repeating: " ", count: width - text.count)
}

@MainActor
private final class Fixtures {
    let shell: String
    let marker = "ma-probe-\(UUID().uuidString.prefix(8))"
    /// The executable name the fake agent list calls a coding session.
    var sessionExe: String { "\(marker)-session" }
    /// The fixture app's name (and the container app the fixture list names).
    var appName: String { "Fixture\(marker.suffix(4))" }
    var started: [Int32] = []
    var failed = false
    let scratch = FileManager.default.temporaryDirectory.appending(path: "ma-probe-\(UUID().uuidString.prefix(8))")

    init(shell: String) {
        self.shell = shell
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "ok  " : "FAIL") \(name): \(detail)")
        if !ok { failed = true }
    }

    func run(_ path: String, _ arguments: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return text
    }

    /// The pid of a process whose command line carries `tag`, once it exists.
    /// `detachedOnly`: its parent must be launchd.
    /// `execed`: skip the wrapper's own subshell, which carries the tag until it has exec'd into the fixture.
    func find(_ tag: String, detachedOnly: Bool = true, execed: Bool = true) async -> Int32? {
        for _ in 0..<20 {
            for line in run("/bin/ps", ["-ax", "-o", "pid=,ppid=,command="]).split(separator: "\n")
            where line.contains(tag) && !line.contains("/bin/ps") && !line.contains("AgentRunner")
                && !(execed && line.contains("</dev/null >/dev/null")) {
                let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard fields.count == 3, let pid = Int32(fields[0]) else { continue }
                if !detachedOnly || fields[1] == "1" { return pid }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// Waits (with a deadline, never a fixed sleep) until the fixture and what it has started have exec'd and
    /// no longer show a command line the app could not yet believe. Returns false at the deadline.
    @discardableResult
    func settle(_ root: Int32, seconds: Double = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let all = [root] + ProcessTree.descendants(of: root)
            if all.allSatisfy({ GuardControl.commandLineDoubt(pid: $0) == nil }) { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    /// Starts `shellCommand` detached; `tag` appears in the resulting command line.
    func detach(_ shellCommand: String, tag: String, settled: Bool = true) async -> Int32? {
        let wrapper = Process()
        wrapper.executableURL = URL(fileURLWithPath: "/bin/bash")
        wrapper.arguments = ["-c", "( \(shellCommand) ) </dev/null >/dev/null 2>&1 &"]
        try? wrapper.run()
        wrapper.waitUntilExit()
        guard let pid = await find(tag, execed: settled) else { return nil }
        started.append(pid)
        if settled { await settle(pid) }
        return pid
    }

    /// `exec -a <name>` + this probe's shell: a process that looks like `name` to the census.
    func detachNamed(_ name: String?, script: String, tag: String, settled: Bool = true) async -> Int32? {
        let head = name.map { "exec -a \($0) \(shell)" } ?? "exec \(shell)"
        return await detach("\(head) -c '\(script)'", tag: tag, settled: settled)
    }

    func program(_ root: Int32, settled: Bool = true) async -> StopTarget? {
        if settled { await settle(root) }
        for _ in 0..<10 {
            if let found = MemoryCensus.take().groups.flatMap(\.programs)
                .first(where: { $0.members.contains { $0.pid == Int(root) } }) { return found }
            try? await Task.sleep(for: .milliseconds(300))
        }
        let holder = MemoryCensus.take().groups.first { $0.members.contains { $0.pid == Int(root) } }
        print("       (pid \(root): in group \(holder?.name ?? "none"), category \(holder.map { "\($0.category)" } ?? "-"), programs \(holder?.programs.count ?? 0))")
        return nil
    }

    /// The probe's own guard: every member of the program is the fixture or under it.
    func contained(_ t: StopTarget, root: Int32) -> Bool {
        let allowed = Set([root] + ProcessTree.descendants(of: root))
        return t.members.allSatisfy { allowed.contains(Int32($0.pid)) }
    }

    func gone(_ pid: Int32) -> Bool { kill(pid, 0) != 0 }
    func alive(_ pid: Int32) -> Bool { !gone(pid) }

    func end(_ root: Int32) {
        for pid in ProcessTree.descendants(of: root) + [root] { kill(pid, SIGKILL) }
    }

    /// An interactive shell (argv0 `zsh`, no `-c`) fed `input`.
    func shellFixture(_ input: String, tag: String) async -> Int32? {
        let fifo = scratch.appending(path: "\(tag).fifo").path
        let rc = scratch.appending(path: "\(tag).rc").path
        _ = run("/usr/bin/mkfifo", [fifo])
        FileManager.default.createFile(atPath: rc, contents: Data())
        // the shell opens the fifo before it execs, so it is found as the wrapper and execs once it is fed
        guard let pid = await detach("exec -a zsh \(shell) --noprofile --init-file '\(rc)' -i < '\(fifo)'", tag: rc, settled: false) else { return nil }
        feed(fifo, input)
        try? await Task.sleep(for: .milliseconds(800))
        await settle(pid)
        return pid
    }

    func feed(_ fifo: String, _ input: String) {
        if let writer = FileHandle(forWritingAtPath: fifo) {
            try? writer.write(contentsOf: Data(input.utf8))
            try? writer.close()
        }
    }

    func cleanup() {
        for pid in started { end(pid) }
        try? FileManager.default.removeItem(at: scratch)
    }
}

/// Runs this probe again with its parent set to launchd, so no case that signals runs from a
/// shell that is a child of a coding session, and prints what it prints. Never returns.
private func relaunchDetached(_ args: [String]) -> Never {
    let scratch = FileManager.default.temporaryDirectory.appending(path: "ma-probe-run-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let out = scratch.appending(path: "out.txt").path
    let status = scratch.appending(path: "status.txt").path
    FileManager.default.createFile(atPath: out, contents: Data())
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    let wrapper = Process()
    wrapper.executableURL = URL(fileURLWithPath: "/bin/bash")
    wrapper.arguments = ["-c", "( \"$0\" \"$@\" --detached-child </dev/null >\"$OUT\" 2>&1; echo $? >\"$STATUS\" ) &", exe] + args
    wrapper.environment = ["OUT": out, "STATUS": status, "PATH": "/usr/bin:/bin"]
    try? wrapper.run()
    wrapper.waitUntilExit()
    var printed = 0
    for _ in 0..<2400 {   // up to four minutes
        if let data = FileManager.default.contents(atPath: out), data.count > printed {
            FileHandle.standardOutput.write(data[printed...])
            printed = data.count
        }
        if let code = (try? String(contentsOfFile: status, encoding: .utf8)).flatMap({ Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
            if let data = FileManager.default.contents(atPath: out), data.count > printed { FileHandle.standardOutput.write(data[printed...]) }
            try? FileManager.default.removeItem(at: scratch)
            exit(code)
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    print("the detached probe did not finish in four minutes")
    exit(1)
}

@MainActor func probeStopTargets(_ args: [String]) async -> Never {
    if !args.contains("--detached-child") { relaunchDetached(args) }
    // the real list of the checkout under test, plus one fixture "agent" for the reach cases
    let root = probeRoot(args)
    guard let realList = try? String(contentsOf: root.appending(path: "lib/coding-agents.tsv"), encoding: .utf8),
          realList.contains("\texe\tclaude") else {
        print("the coding-agent list was not found under \(root.path) (pass --root <checkout>): the stop guards were NOT run")
        exit(2)
    }
    guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/bash") else {
        print("no shell outside the system folders to use as a fixture: the guard cases were NOT run")
        exit(2)
    }
    let f = Fixtures(shell: "/opt/homebrew/bin/bash")
    let fixtureList = f.scratch.appending(path: "agents.tsv")
    try? (realList + "\nFixture Agent\texe\t\(f.sessionExe)\n-\tcontainer\t\(f.appName)\n").write(to: fixtureList, atomically: true, encoding: .utf8)
    CodingAgentHosts.useList(at: fixtureList)
    let missingList = f.scratch.appending(path: "not-there.tsv")

    listPrograms()
    print("\nguards, with throwaway processes (all started and ended here):")
    await basicGuards(f)
    await sessionGuards(f)
    await reachCases(f)
    await failClosedCases(f, restore: fixtureList, missing: missingList)
    await quitAndLinkCases(f)
    await reloadCase(f, original: realList + "\nFixture Agent\texe\t\(f.sessionExe)\n", at: fixtureList)
    await hostedSessionsCase(f, restore: fixtureList, missing: missingList)
    await confirmationCase(f)
    await unsettledCase(f)
    await judgementCases(f)
    await zombieCase(f)
    await titleRewriteCases(f)
    f.cleanup()
    exit(f.failed ? 1 : 0)
}

// MARK: - what a Stop would offer

@MainActor private func listPrograms() {
    let census = MemoryCensus.take()
    print("separate programs in command-line tool groups (what a group Stop would offer):\n")
    var locked = 0, free = 0
    for group in census.groups(in: .tools).filter({ $0.programs.count > 1 }).prefix(6) {
        print("\(MonitorTree.rowName(group.name)) — \(group.programs.count) programs")
        for program in group.programs.prefix(8) {
            let state = program.lockedReason ?? (program.isStoppable ? "can be stopped" : "not yours to stop")
            print("    " + pad(program.name, 26) + pad(program.whereItRuns.map { "in \($0)" } ?? "", 26)
                  + pad(program.totalText, 10) + state)
        }
    }
    for group in census.groups(in: .tools) {
        for program in group.programs { program.lockedBy == nil ? (free += 1) : (locked += 1) }
    }
    print("\nall tool programs: \(free + locked) — \(locked) locked to a coding session, \(free) free")
}

// MARK: - identity checks

@MainActor private func basicGuards(_ f: Fixtures) async {
    // a stale start time is refused, the real one is signalled
    let sleeper = Process()
    sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleeper.arguments = ["60"]
    try? sleeper.run()
    try? await Task.sleep(for: .milliseconds(300))
    if let identity = ProcessIdentity.of(pid: Int(sleeper.processIdentifier)) {
        let stale = ProcessIdentity(pid: identity.pid, birth: ProcessTree.Birth(seconds: identity.birth.seconds - 1,
                                                                                 microseconds: identity.birth.microseconds))
        f.check("stale start time (one second off)", GuardControl.stop([stale]).isEmpty, "refused")
        let reached = GuardControl.stop([identity]).count == 1
        sleeper.waitUntilExit()
        f.check("the real start time", reached, "stopped (exit \(sleeper.terminationStatus))")
    }

    // a stop with no identity is refused
    let lone = Process()
    lone.executableURL = URL(fileURLWithPath: "/bin/sleep")
    lone.arguments = ["64"]
    try? lone.run()
    try? await Task.sleep(for: .milliseconds(300))
    if let live = LiveStats.process(pid: Int(lone.processIdentifier)) {
        let result = GuardControl.stopProcess(live, identity: nil)
        var refused = false
        if case .refused = result { refused = true }
        f.check("a stop with no identity", refused && f.alive(lone.processIdentifier), "\(result)")
    }
    lone.terminate(); lone.waitUntilExit()

    // a live session's pid is refused
    if let agent = await f.detachNamed("claude", script: ": \(f.marker)-a; sleep 60; :", tag: "\(f.marker)-a"),
       let live = LiveStats.process(pid: Int(agent)) {
        let result = GuardControl.stopProcess(live, identity: live.identity)
        var refused = false
        if case .refused = result { refused = true }
        f.check("stopProcess on a live `claude` session's pid", refused && f.alive(agent), "\(result)")
        f.end(agent)
    } else { f.check("stopProcess on a live `claude` session's pid", false, "fixture not found") }
}

// MARK: - what is locked

@MainActor private func sessionGuards(_ f: Fixtures) async {
    if let host = await f.detachNamed("claude", script: ": \(f.marker)-b; sleep 60; :", tag: "\(f.marker)-b") {
        if let t = await f.program(host) {
            f.check("a tree with a `claude` session inside", f.contained(t, root: host) && t.lockedReason != nil,
                    t.lockedReason ?? "NOT locked")
        } else { f.check("a tree with a `claude` session inside", false, "program not found") }
        f.end(host)
    } else { f.check("a tree with a `claude` session inside", false, "fixture not found") }

    if let shell = await f.shellFixture("(exec -a claude /bin/sleep 60) &\nwait\n", tag: "\(f.marker)-c") {
        if let t = await f.program(shell) {
            f.check("a shell that hosts a `claude` session", f.contained(t, root: shell) && (t.lockedBy != nil || !t.hostedSessions.isEmpty) && !t.isStoppable,
                    "locked by \(t.lockedBy ?? "nothing"), hosts \(t.hostedSessions); stoppable: \(t.isStoppable)")
        } else { f.check("a shell that hosts a `claude` session", false, "program not found") }
        f.end(shell)
    } else { f.check("a shell that hosts a `claude` session", false, "fixture not found") }

    if let shell = await f.shellFixture("sleep 60 &\nwait\n", tag: "\(f.marker)-d") {
        if let t = await f.program(shell) {
            f.check("an interactive shell with no agent", f.contained(t, root: shell) && !t.isStoppable && t.lockedReason != nil,
                    t.lockedReason ?? "offered Stop")
        } else { f.check("an interactive shell with no agent", false, "program not found") }
        f.end(shell)
    } else { f.check("an interactive shell with no agent", false, "fixture not found") }
}

// MARK: - what one Stop reaches

@MainActor private func reachCases(_ f: Fixtures) async {
    // Stop is polite; force is a second, separate step. A root that ignores SIGTERM, with
    // children the census does not list: the polite stop kills NOTHING, and only the
    // Force Stop the person confirms ends it.
    if let root = await f.detachNamed(nil, script: ": \(f.marker)-e; trap \"\" TERM; sleep 61 & sleep 62 & wait; :", tag: "\(f.marker)-e") {
        if let t = await f.program(root), f.contained(t, root: root) {
            let before = t.memberIdentities.count
            let children = ProcessTree.descendants(of: root)
            let sheetRow = MemoryStop.reachText(of: t)
            f.check("the group sheet's row says what the stop would reach", sheetRow == "and \(children.count) processes it started",
                    sheetRow ?? "nothing said")
            let ask = await GuardControl.askProgramToStop(t.memberIdentities, name: t.label, grace: .seconds(1))
            f.check("the polite stop kills nothing (a program that ignores SIGTERM)",
                    ask.refusal == nil && !ask.stillRunning.isEmpty && f.alive(root) && children.allSatisfy(f.alive),
                    "asked \(ask.asked), still running \(ask.stillRunning.count) of them, nothing forced")
            print("       summary: \(MemoryStop.programSummary(t.label, ask))")
            let offer = MemoryStop.forceOffer(t.label, ask.stillRunning)
            print("       second question: \(offer.title) — \(offer.detail)")
            let report = await offer.run()
            f.check("Force Stop, once confirmed, ends it (listed \(before), children \(children.count))",
                    f.gone(root) && children.allSatisfy(f.gone), report.message)
        } else { f.check("the polite stop kills nothing", false, "program not found, or not contained: refusing to signal") }
        f.end(root)
    } else { f.check("the polite stop kills nothing", false, "fixture not found") }

    // a session that appears AFTER the polite step refuses the Force Stop (reach, locks and start times are recomputed)
    // the session starts from its own shell with its own command line, not from a subshell: a subshell shows
    // its parent's command line, which the app rightly refuses to act on for its first moments (`unsettledCase`)
    let late = ": \(f.marker)-q; trap \"\" TERM; \(f.shell) -c \"sleep 3; exec -a \(f.sessionExe) \(f.shell) -c \\\": \(f.marker)-q2; sleep 73; :\\\"\" & while :; do sleep 1; done"
    if let root = await f.detachNamed(nil, script: late, tag: "\(f.marker)-q") {
        if let identity = ProcessIdentity.of(pid: Int(root)) {
            let ask = await GuardControl.askProgramToStop([identity], name: "Fixture program", grace: .seconds(1))
            f.check("  (the polite step ran before the session existed)", ask.refusal == nil && !ask.stillRunning.isEmpty, "still running \(ask.stillRunning.count)")
            try? await Task.sleep(for: .seconds(3))
            let forced = await GuardControl.forceStopProgram(ask.stillRunning, name: "Fixture program")
            f.check("a session that appeared meanwhile refuses the Force Stop",
                    forced.refusal?.contains("Fixture Agent") == true && f.alive(root), forced.refusal ?? "NOT refused")
        }
        f.end(root)
    } else { f.check("a session that appeared meanwhile refuses the Force Stop", false, "fixture not found") }

    // a program with a SECOND program nested under its shell (no session in it): allowed, and the second survives
    let fifo = f.scratch.appending(path: "\(f.marker)-g.fifo").path
    let rc = f.scratch.appending(path: "\(f.marker)-g.rc").path
    _ = f.run("/usr/bin/mkfifo", [fifo])
    FileManager.default.createFile(atPath: rc, contents: Data())
    let nestedScript = ": \(f.marker)-g; ( exec -a zsh \(f.shell) --noprofile --init-file \(rc) -i < \(fifo) ) & wait; :"
    if let outer = await f.detachNamed("node", script: nestedScript, tag: "\(f.marker)-g") {
        f.feed(fifo, "( exec -a \(f.marker)-g-inner /bin/sleep 66 ) &\nwait\n")
        let shellPID = await f.find("zsh --noprofile --init-file \(rc)", detachedOnly: false)
        let innerPID = await f.find("\(f.marker)-g-inner", detachedOnly: false)
        if let t = await f.program(outer), f.contained(t, root: outer), let shellPID, let innerPID {
            let result = await GuardControl.askProgramToStop(t.memberIdentities, name: t.label, grace: .seconds(1))
            f.check("a parent whose terminals hold no session is allowed, and the program under its shell survives",
                    f.gone(outer) && f.alive(shellPID) && f.alive(innerPID) && result.refusal == nil,
                    "outer program gone: \(f.gone(outer)); nested shell alive: \(f.alive(shellPID)); the program under it alive: \(f.alive(innerPID))")
        } else { f.check("a parent whose terminals hold no session is allowed", false, "fixtures not found") }
        f.end(outer)
        if let shellPID { f.end(shellPID) }
    } else { f.check("a parent whose terminals hold no session is allowed", false, "fixture not found") }

    await hostedTerminalCases(f)

    // a member that holds a fake session: the whole Stop is refused, at the Stop itself
    // (the census marks the program locked too; this skips that layer to prove the Stop's own check)
    if let host = await f.detachNamed(nil, script: ": \(f.marker)-h; ( exec -a \(f.sessionExe) \(f.shell) -c \": \(f.marker)-h2; sleep 67; :\" ) & wait; :", tag: "\(f.marker)-h") {
        let sessionPID = await f.find("\(f.sessionExe) -c", detachedOnly: false)
        if let identity = ProcessIdentity.of(pid: Int(host)), let sessionPID {
            let result = await GuardControl.askProgramToStop([identity], name: "Fixture program", grace: .seconds(1))
            f.check("  (the session found is not the program itself)", sessionPID != host, "pids \(host) and \(sessionPID)")
            f.check("a program holding a fake session is refused by the Stop itself",
                    result.refusal?.contains("Fixture Agent") == true && f.alive(host) && f.alive(sessionPID),
                    result.refusal ?? "NOT refused")
            if let t = await f.program(host) {
                f.check("  ... and the census marks it locked", t.lockedBy == "Fixture Agent" || t.hostedSessions["Fixture Agent"] == 1,
                        "locked by \(t.lockedBy ?? "nothing"), hosts \(t.hostedSessions)")
            }
        } else { f.check("a program holding a fake session is refused by the Stop itself", false, "fixtures not found") }
        f.end(host)
    } else { f.check("a program holding a fake session is refused by the Stop itself", false, "fixture not found") }

    // an identity that no longer matches (a pid reused by an unrelated process) is never signalled,
    // at the polite step or the forced one. A real reuse cannot be forced (it takes ~100,000 forks), so the
    // listed identity is given a start time that is not the process's own: the same check the reuse trips.
    if let member = await f.detachNamed(nil, script: ": \(f.marker)-j; trap \"\" TERM; sleep 70 & wait; :", tag: "\(f.marker)-j"),
       let bystander = await f.detach("exec -a \(f.marker)-bystander /bin/sleep 68", tag: "\(f.marker)-bystander"),
       let real = ProcessIdentity.of(pid: Int(member)), let genuine = ProcessIdentity.of(pid: Int(bystander)) {
        let reused = ProcessIdentity(pid: genuine.pid, birth: ProcessTree.Birth(seconds: genuine.birth.seconds - 5,
                                                                                 microseconds: genuine.birth.microseconds))
        let ask = await GuardControl.askProgramToStop([real, reused], name: "Fixture program", grace: .seconds(1))
        let forced = await GuardControl.forceStopProgram(ask.stillRunning + [reused], name: "Fixture program")
        f.check("a listed pid that was reused by an unrelated process survives both steps",
                f.alive(bystander) && f.gone(member) && ask.refusal == nil && forced.refusal == nil,
                "bystander alive: \(f.alive(bystander)); the real member (ignored SIGTERM, then forced on request) gone: \(f.gone(member))")
        f.end(member); f.end(bystander)
    } else { f.check("a listed pid that was reused by an unrelated process survives both steps", false, "fixtures not found") }

    // never an ancestor: this process (asserted from the reach, nothing is called that signals), and a child's stop leaving its parent
    if let own = ProcessIdentity.of(pid: Int(getpid())) {
        let refusal = GuardControl.reachRefusal(listed: [own], name: "This probe")
        f.check("a Stop that would reach Mac Analyzers itself is refused by the reach alone", refusal?.contains("itself") == true,
                refusal ?? "NOT refused")
    }
    if let parent = await f.detachNamed(nil, script: ": \(f.marker)-k; ( exec -a \(f.marker)-child /bin/sleep 71 ) & while :; do sleep 1; done", tag: "\(f.marker)-k"),
       let childPID = await f.find("\(f.marker)-child 71", detachedOnly: false),
       let child = ProcessIdentity.of(pid: Int(childPID)) {
        let result = await GuardControl.askProgramToStop([child], name: "Fixture child", grace: .seconds(1))
        f.check("stopping a child never signals its parent", f.gone(childPID) && f.alive(parent) && result.refusal == nil,
                "child gone: \(f.gone(childPID)); parent alive: \(f.alive(parent))")
        f.end(parent)
    } else { f.check("stopping a child never signals its parent", false, "fixtures not found") }

    // what counts as an interactive shell (a terminal) and what does not
    let table: [(String, Bool)] = [
        ("zsh", true), ("-zsh", true), ("/bin/zsh -f -i", true),
        ("bash --noprofile --init-file /tmp/x.rc -i", true), ("bash -l", true),
        ("bash -lc some command", false), ("zsh -c source x", false), ("sh -c echo hi", false),
        ("bash /Users/x/mac-analyzers/memory-analyzer/memory-guard.sh", false), ("node server.js", false)]
    let wrong = table.filter { GuardControl.isInteractiveShell(command: $0.0) != $0.1 }
    f.check("what counts as a terminal session", wrong.isEmpty,
            wrong.isEmpty ? "\(table.count) command lines classified as intended" : "wrong: \(wrong.map(\.0))")
}

// MARK: - a program that HOSTS terminals

/// Ending a program that owns terminal sessions (a terminal's server, tmux) closes the terminals and
/// every coding session in them. The reach does not enter those shells, so the check has to look
/// below them: one level, two levels, and the single-process stop.
@MainActor private func hostedTerminalCases(_ f: Fixtures) async {
    let session = "exec -a \(f.sessionExe) \(f.shell) -c"
    func feedShell(_ input: String, tag: String) -> (rc: String, fifo: String) {
        let fifo = f.scratch.appending(path: "\(tag).fifo").path
        let rc = f.scratch.appending(path: "\(tag).rc").path
        _ = f.run("/usr/bin/mkfifo", [fifo])
        FileManager.default.createFile(atPath: rc, contents: Data())
        return (rc, fifo)
    }

    // level 1: a non-shell parent -> an interactive shell -> a session
    let one = feedShell("", tag: "\(f.marker)-t1")
    let script1 = ": \(f.marker)-t1; ( exec -a zsh \(f.shell) --noprofile --init-file \(one.rc) -i < \(one.fifo) ) & while :; do sleep 1; done"
    if let host = await f.detachNamed("node", script: script1, tag: "\(f.marker)-t1") {
        f.feed(one.fifo, "(\(session) \": \(f.marker)-t1s; sleep 74; :\") &\nwait\n")
        let shellPID = await f.find("zsh --noprofile --init-file \(one.rc)", detachedOnly: false)
        let sessionPID = await f.find("\(f.sessionExe) -c : \(f.marker)-t1s", detachedOnly: false)
        try? await Task.sleep(for: .milliseconds(500))
        if let t = await f.program(host), f.contained(t, root: host), let shellPID, let sessionPID {
            f.check("a parent of terminals: the census locks it and says what it hosts", !t.isStoppable && t.hostedSessions["Fixture Agent"] == 1,
                    t.lockedReason ?? "offered Stop")
            var plan = "no refusal"
            if case .refused(let why) = MemoryStop.plan(target: t) { plan = why }
            f.check("  ... and the plan is refused with the same sentence", plan.contains("hosts 1 live Fixture Agent session"), plan)
            let ask = await GuardControl.askProgramToStop(t.memberIdentities, name: t.label, grace: .seconds(1))
            f.check("  ... and the Stop itself refuses (the reach skips the shell; the check looks below it)",
                    ask.refusal?.contains("hosts 1 live Fixture Agent session") == true,
                    ask.refusal ?? "NOT refused")
            f.check("  ... and everything is still running afterwards", f.alive(host) && f.alive(shellPID) && f.alive(sessionPID),
                    "parent \(f.alive(host)), shell \(f.alive(shellPID)), session \(f.alive(sessionPID))")
            if let live = LiveStats.process(pid: Int(host)), let identity = live.identity {
                var refused = false
                if case .refused = GuardControl.stopProcess(live, identity: identity) { refused = true }
                f.check("  ... and the single-process stop refuses it too", refused && f.alive(host), "")
            }
        } else { f.check("a parent of terminals", false, "fixtures not found") }
        f.end(host)
        if let shellPID = await f.find("zsh --noprofile --init-file \(one.rc)", detachedOnly: false) { f.end(shellPID) }
    } else { f.check("a parent of terminals", false, "fixture not found") }

    // level 2: a non-shell parent -> an interactive shell -> a non-shell -> a session
    let two = feedShell("", tag: "\(f.marker)-t2")
    let script2 = ": \(f.marker)-t2; ( exec -a zsh \(f.shell) --noprofile --init-file \(two.rc) -i < \(two.fifo) ) & while :; do sleep 1; done"
    if let host = await f.detachNamed("node", script: script2, tag: "\(f.marker)-t2") {
        f.feed(two.fifo, "( exec -a node \(f.shell) -c ': \(f.marker)-t2m; (\(session) \": \(f.marker)-t2s; sleep 75; :\") & while :; do sleep 1; done' ) &\nwait\n")
        let sessionPID = await f.find("\(f.sessionExe) -c : \(f.marker)-t2s", detachedOnly: false)
        try? await Task.sleep(for: .milliseconds(500))
        if let identity = ProcessIdentity.of(pid: Int(host)), let sessionPID {
            let refusal = GuardControl.reachRefusal(listed: [identity], name: "Fixture parent")
            let ask = await GuardControl.askProgramToStop([identity], name: "Fixture parent", grace: .seconds(1))
            f.check("two levels below a terminal: refused, and everything is still running",
                    refusal?.contains("hosts 1 live Fixture Agent session") == true && ask.refusal != nil && f.alive(host) && f.alive(sessionPID),
                    ask.refusal ?? "NOT refused")
        } else { f.check("two levels below a terminal", false, "fixtures not found") }
        f.end(host)
        if let shellPID = await f.find("zsh --noprofile --init-file \(two.rc)", detachedOnly: false) { f.end(shellPID) }
    } else { f.check("two levels below a terminal", false, "fixture not found") }
}

// MARK: - the list is unavailable

@MainActor private func failClosedCases(_ f: Fixtures, restore: URL, missing: URL) async {
    guard let root = await f.detachNamed(nil, script: ": \(f.marker)-l; sleep 72; :", tag: "\(f.marker)-l") else {
        f.check("list missing: every tool stop refused", false, "fixture not found")
        return
    }
    let census = MemoryCensus.take()
    CodingAgentHosts.useList(at: missing)
    var refused = 0, total = 0
    func expect(_ name: String, _ ok: Bool, _ detail: String) {
        total += 1
        if ok { refused += 1 }
        f.check("list missing: \(name)", ok, detail)
    }
    expect("the list reads as unavailable", !CodingAgentHosts.isAvailable, CodingAgentHosts.unavailableSentence)
    if let t = census.groups.flatMap(\.programs).first(where: { $0.members.contains { $0.pid == Int(root) } }) {
        expect("the program shows no Stop", !t.isStoppable && t.lockedReason == CodingAgentHosts.unavailableSentence,
               t.lockedReason ?? "offered Stop")
        var plan = false
        if case .refused(let why) = MemoryStop.plan(target: t) { plan = why == CodingAgentHosts.unavailableSentence }
        expect("MemoryStop.plan(target:) refuses", plan, "")
        let result = await GuardControl.askProgramToStop(t.memberIdentities, name: t.label, grace: .seconds(1))
        expect("the polite stop refuses and nothing is signalled", result.refusal == CodingAgentHosts.unavailableSentence && f.alive(root),
               result.refusal ?? "NOT refused")
        let rows = MonitorTree.rows(census: census)
        let anyStop = rows.flatMap { [$0] + $0.children + $0.children.flatMap(\.children) }.contains { row in
            if case .stopProgram = row.stop { return true }
            if case .stopProcess = row.stop { return true }
            if case .choosePrograms = row.stop { return true }
            return false
        }
        expect("no Monitor row offers a Stop on a tool", !anyStop, anyStop ? "a row still offers Stop" : "every tool row is unavailable")
    } else { expect("the fixture program was found", false, "not found") }
    if let live = LiveStats.process(pid: Int(root)), let identity = live.identity {
        var processRefused = false
        if case .refused(let why) = GuardControl.stopProcess(live, identity: identity) { processRefused = why == CodingAgentHosts.unavailableSentence }
        expect("stopProcess refuses a tool process", processRefused && f.alive(root), "")
        expect("stop([identity]) signals nothing", GuardControl.stop([identity]).isEmpty && f.alive(root), "")
    }
    if let group = census.groups(in: .tools).first(where: { $0.programs.contains { $0.members.contains { $0.pid == Int(root) } } }) {
        var groupPlan = false
        if case .refused(let why) = MemoryStop.plan(group: group) { groupPlan = why == CodingAgentHosts.unavailableSentence }
        expect("MemoryStop.plan(group:) refuses", groupPlan, "")
    }
    print("       \(refused) of \(total) refused with the list missing; the fixture is still running: \(f.alive(root))")
    CodingAgentHosts.useList(at: restore)
    f.end(root)
}

// MARK: - the Quit dialog's sentence about hosted sessions

@MainActor private func hostedSessionsCase(_ f: Fixtures, restore: URL, missing: URL) async {
    // an app-shaped tree: a copy of the shell inside a fake bundle, with a fixture session under it
    let bundle = f.scratch.appending(path: "\(f.appName).app/Contents/MacOS")
    let exe = bundle.appending(path: "Fixture")
    try? FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try? FileManager.default.copyItem(atPath: URL(fileURLWithPath: f.shell).resolvingSymlinksInPath().path, toPath: exe.path)
    let script = ": \(f.marker)-m; ( exec -a \(f.sessionExe) \(f.shell) -c \": \(f.marker)-m2; sleep 69; :\" ) & wait; :"
    guard let app = await f.detach("exec '\(exe.path)' -c '\(script)'", tag: "\(f.marker)-m") else {
        f.check("an app that hosts a live session", false, "fixture not found")
        return
    }
    // the session under the fixture app starts a moment after the app does: look until the census sees it
    // (up to ten seconds), so a busy Mac does not turn a slow start into a failure
    var census = MemoryCensus.take()
    for _ in 0..<20 {
        let seen = census.groups.first { $0.members.contains { $0.pid == Int(app) } }?.hostedSessions["Fixture Agent"] == 1
        if seen { await f.settle(app); break }
        try? await Task.sleep(for: .milliseconds(500))
        census = MemoryCensus.take()
    }
    if let group = census.groups.first(where: { $0.members.contains { $0.pid == Int(app) } }) {
        f.check("an app-shaped group counts the session inside it", group.category == .apps && group.hostedSessions["Fixture Agent"] == 1,
                "category \(group.category), hosted \(group.hostedSessions)")
        var line = "no confirmation"
        if case .confirm(let pending) = MemoryStop.plan(group: group) { line = pending.detail }
        f.check("the Quit dialog names the session", line.contains("1 live Fixture Agent session runs inside it and will end with it."), line)
        f.check("an app on the container list adds that containers will stop", line.contains("Containers running in it will stop."), line)
        f.check("the real container apps are on the list, whatever their case",
                CodingAgentHosts.isContainerRuntime(appName: "orbstack") && CodingAgentHosts.isContainerRuntime(appName: "Docker Desktop")
                    && !CodingAgentHosts.isContainerRuntime(appName: "Safari"), "OrbStack, Docker Desktop yes; Safari no")
        CodingAgentHosts.useList(at: missing)
        var unchecked = "no confirmation"
        if case .confirm(let pending) = MemoryStop.plan(group: group) { unchecked = pending.detail }
        f.check("with the list missing the Quit dialog says it could not check", unchecked.contains("could not check"), unchecked)
        CodingAgentHosts.useList(at: restore)
        f.check("planning the Quit signalled nothing", f.alive(app), "the fixture app is still running")
    } else { f.check("an app-shaped group counts the session inside it", false, "group not found") }
    f.end(app)
}

// MARK: - nothing happens without a confirmation

@MainActor private func confirmationCase(_ f: Fixtures) async {
    if let root = await f.detachNamed(nil, script: ": \(f.marker)-f; sleep 63; :", tag: "\(f.marker)-f") {
        if let t = await f.program(root), f.contained(t, root: root) {
            let outcome = MemoryStop.plan(target: t)
            var isConfirm = false
            if case .confirm = outcome { isConfirm = true }
            f.check("MemoryStop.plan(target:) sends nothing", isConfirm && f.alive(root), outcome.message)
            if case .confirm(let pending) = outcome { _ = await pending.run() }
            f.check("  ... and confirming does", t.memberIdentities.allSatisfy { !$0.isStillRunning }, "stopped")
        } else { f.check("MemoryStop.plan(target:)", false, "program not found, or not contained") }
        f.end(root)
    }
    let fresh = MemoryCensus.take()
    if let claude = fresh.groups(in: .tools).first(where: { !$0.programs.isEmpty && $0.programs.allSatisfy { $0.lockedBy != nil } }) {
        print("  MemoryStop.plan(group: \(MonitorTree.rowName(claude.name))): \(MemoryStop.plan(group: claude).message)")
    }
    if let several = fresh.groups(in: .tools).first(where: { $0.programs.filter(\.isStoppable).count > 0 && $0.programs.count > 1 }) {
        let outcome = MemoryStop.plan(group: several)
        if case .needsChoice(_, let link) = outcome {
            print("  MemoryStop.plan(group: \(MonitorTree.rowName(several.name))): \(outcome.message)  [link: \(link)]")
        } else { f.check("a group of several programs needs a choice", false, "\(outcome)") }
    }
}

// MARK: - the list is read again when the file changes

@MainActor private func reloadCase(_ f: Fixtures, original: String, at url: URL) async {
    let probe = f.scratch.appending(path: "reload.tsv")
    try? original.write(to: probe, atomically: true, encoding: .utf8)
    CodingAgentHosts.useList(at: probe)
    let before = CodingAgentHosts.isAvailable
    // a pull that empties the list takes effect without a relaunch (the date is looked at once a second)
    try? await Task.sleep(for: .milliseconds(1300))
    try? "# nothing\n".write(to: probe, atomically: true, encoding: .utf8)
    try? await Task.sleep(for: .milliseconds(1300))
    let emptied = !CodingAgentHosts.isAvailable
    try? await Task.sleep(for: .milliseconds(1300))
    try? original.write(to: probe, atomically: true, encoding: .utf8)
    try? await Task.sleep(for: .milliseconds(1300))
    let restored = CodingAgentHosts.isAvailable
    f.check("the list is read again when the file changes", before && emptied && restored,
            "available \(before), after the file was emptied: \(!emptied ? "still available" : "unavailable"), after it was restored: \(restored ? "available" : "unavailable")")
    CodingAgentHosts.useList(at: url)
}

// MARK: - Quit on something that is not a running app, and the reasons a link may carry

@MainActor private func quitAndLinkCases(_ f: Fixtures) async {
    // an "app group" whose root is not a running app (a tool in an app's folder) hosting a session: Quit refuses
    if let root = await f.detachNamed(nil, script: ": \(f.marker)-r; ( exec -a \(f.sessionExe) \(f.shell) -c \": \(f.marker)-r2; sleep 76; :\" ) & wait; :", tag: "\(f.marker)-r") {
        if let identity = ProcessIdentity.of(pid: Int(root)) {
            let reached = GuardControl.quitApp([identity])
            f.check("Quit on a process that is not a running app refuses when it hosts a session", reached.isEmpty && f.alive(root),
                    "reached \(reached.count); still running: \(f.alive(root))")
        }
        f.end(root)
    } else { f.check("Quit on a process that is not a running app refuses when it hosts a session", false, "fixture not found") }

    // a link carries a reason code; the app writes the sentence; anything else shows nothing
    let known = StopWhy(code: "changed") == .changed && StopWhy(code: "unverifiable") == .unverifiable
        && StopWhy(code: "hosts.Claude%20Code") == .hosts("Claude Code")
    let spoofed = ["Your Mac is infected, call 555", "hosts.Fake%20Agent", "session.", "changed.extra", "", "refused.Claude%20Code"]
        .filter { StopWhy(code: $0) != nil }
    f.check("a link's reason is a code the app understands", known && spoofed.isEmpty,
            spoofed.isEmpty ? "known codes read; \(6) invented ones show nothing" : "accepted: \(spoofed)")
    f.check("the sentence is the app's own", StopWhy.hosts("Claude Code").sentence.hasPrefix("This process hosts live Claude Code sessions"),
            StopWhy.hosts("Claude Code").sentence)
}

// MARK: - a program that has not become itself yet is not stopped

/// A subshell shows its parent's command line for as long as it lives; for the first moments that is also
/// what a child that is about to exec shows. A Stop looks inside a program for sessions by command line, so
/// it refuses "for now" while any process in it only repeats its parent's, and works once it is settled. A
/// Quit warns instead (it is the person's own ⌘Q) and never signals what it cannot tell.
///
/// The young process is made ON DEMAND, by a file this probe creates, so it is looked at within a fraction of
/// a second of its start whatever the machine is doing; if the rule is switched off, or the process cannot be
/// found young, this FAILS. There is no "not judged" way out.
@MainActor private func unsettledCase(_ f: Fixtures) async {
    let go = f.scratch.appending(path: "\(f.marker)-u.go").path
    let script = ": \(f.marker)-u; while [ ! -e \(go) ]; do sleep 0.1; done; ( : \(f.marker)-u2; sleep 11; : ); :"
    guard let root = await f.detachNamed(nil, script: script, tag: "\(f.marker)-u") else {
        f.check("a process still showing its parent's command line", false, "fixture not found")
        return
    }
    guard let identity = ProcessIdentity.of(pid: Int(root)) else {
        f.check("a process still showing its parent's command line", false, "the fixture is not running")
        return
    }
    f.check("before the young process exists nothing is doubted", GuardControl.reachRefusal(listed: [identity], name: "Fixture") == nil,
            "the fixture alone is believed")
    FileManager.default.createFile(atPath: go, contents: Data())
    var doubted: Int32?
    for _ in 0..<60 where doubted == nil {
        doubted = ProcessTree.descendants(of: root).first { GuardControl.commandLineDoubt(pid: $0) != nil }
        if doubted == nil { try? await Task.sleep(for: .milliseconds(50)) }
    }
    f.check("a subshell that has just started repeats its parent's command line, and that is noticed",
            doubted != nil, doubted.flatMap { GuardControl.commandLineDoubt(pid: $0) } ?? "no process under the fixture was doubted")

    let stop = GuardControl.reachRefusal(listed: [identity], name: "Fixture")
    f.check("  ... so a Stop refuses for now, and says it could not tell", stop?.contains("could not tell") == true, stop ?? "NOT refused")
    f.check("  ... and signalled nothing", f.alive(root), "the fixture is still running")
    let quit = MemoryStop.quitReach(of: [identity], name: "Fixture")
    f.check("  ... and a Quit's dialog says it could not yet see what is inside", quit.caution?.contains("could not yet tell") == true, quit.caution ?? "NO caution")
    let sent = GuardControl.quitApp([identity])
    f.check("  ... and a quit that would be a SIGTERM sends nothing", sent.isEmpty && f.alive(root), "asked \(sent.count), fixture alive: \(f.alive(root))")

    let settled = await f.settle(root)
    f.check("  ... and once it has settled it is believed again", settled, settled ? "settled" : "still doubted after 10 s")
    f.check("  ... a Stop is not refused, and the Quit says nothing", GuardControl.reachRefusal(listed: [identity], name: "Fixture") == nil
            && MemoryStop.quitReach(of: [identity], name: "Fixture").caution == nil && f.alive(root), "both clear, nothing signalled")
    if settled, let t = await f.program(root), f.contained(t, root: root) {
        var confirms = false
        if case .confirm = MemoryStop.plan(target: t) { confirms = true }
        f.check("  ... and the program's Stop is a confirmation, still without sending anything", confirms && f.alive(root), "plan(target:) confirms")
    }
    f.end(root)
}

// MARK: - a program that rewrites its title

/// A program that rewrites its own title (Node's `process.title`, which is how `next-server (v16.3.1)` gets its
/// name) overwrites its arguments with the title and fills the rest with NULs. Its command line is the title
/// alone, as `ps` shows. Two things follow, and both are proved here with a real Node process:
///  - a title-rewriting program that hosts a live session is still seen as hosting it (the session is a child,
///    found by its own command line), so a Stop on it is refused;
///  - text that only sits in its ENVIRONMENT (an agent's folder, a `.app/` path) is not part of what it is: it
///    is not a session and not an app, and a Stop on it is offered.
/// Needs a `node` on the login shell's path; without one the cases are not judged and say so.
@MainActor private func titleRewriteCases(_ f: Fixtures) async {
    let node = f.run("/bin/bash", ["-lc", "command -v node"]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard node.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: node) else {
        print("  not judged: no `node` on the login shell's path, so a program that rewrites its title was not tried")
        return
    }
    // 1. a title-rewriting program that hosts a session
    // the session is started the way every other fixture's is, `exec -a <session name>`, from a shell Node starts
    let session = "exec -a \(f.sessionExe) \(f.shell) -c \": \(f.marker)-t2; sleep 41; :\""
    let hostScript = "process.title=\"next-server (v1) \(f.marker)-t\"; "
        + "require(\"child_process\").spawn(\"/bin/bash\",[\"-c\",process.env.SESS],{stdio:\"ignore\"}); setTimeout(()=>{},41000)"
    if let root = await f.detach("SESS='\(session)' exec '\(node)' -e '\(hostScript)'", tag: "\(f.marker)-t") {
        // Node starts, then rewrites its title, then starts the session: wait for the title and the session
        var line = ""
        for _ in 0..<40 where !line.hasPrefix("next-server (v1)") {
            line = f.run("/bin/ps", ["-ww", "-o", "command=", "-p", String(root)]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.hasPrefix("next-server (v1)") { try? await Task.sleep(for: .milliseconds(150)) }
        }
        _ = await f.find(f.sessionExe, detachedOnly: false, execed: false)
        await f.settle(root)
        f.check("a Node program that rewrote its title reads as the title alone", line.hasPrefix("next-server (v1)") && !line.contains("="),
                "the process table shows a title and no environment")
        if let t = await f.program(root), f.contained(t, root: root) {
            let outcome = MemoryStop.plan(target: t)
            var refused = false
            if case .refused = outcome { refused = true }
            f.check("  ... and hosting a session, a Stop on it is refused naming the session",
                    refused && (t.lockedBy != nil || !t.hostedSessions.isEmpty), outcome.message)
            f.check("  ... and nothing was signalled", f.alive(root), "the fixture is still running")
        } else { f.check("  ... and hosting a session, a Stop on it is refused", false, "program not found, or not contained") }
        f.end(root)
    } else { f.check("a title-rewriting program that hosts a session", false, "fixture not found") }

    // 2. a title-rewriting program with agent and app text only in its environment
    let bait = "\(f.sessionExe) /Users/x/.local/share/claude/versions /Applications/Bait\(f.marker.suffix(4)).app/Contents/MacOS/Bait"
    let plain = "process.title=\"bait-title \(f.marker)-b\"; setTimeout(()=>{},41000)"
    if let root = await f.detach("FIXTURE_BAIT='\(bait)' exec '\(node)' -e '\(plain)'", tag: "\(f.marker)-b") {
        var shown = ""
        for _ in 0..<40 where !shown.hasPrefix("bait-title") {
            shown = f.run("/bin/ps", ["-ww", "-o", "command=", "-p", String(root)]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !shown.hasPrefix("bait-title") { try? await Task.sleep(for: .milliseconds(150)) }
        }
        await f.settle(root)
        let agent = CodingAgentHosts.liveSessionAgent(pid: Int(root))
        f.check("an agent's name in the environment alone does not make a program a session", agent == nil, "agent: \(agent ?? "none")")
        if let t = await f.program(root), f.contained(t, root: root) {
            let group = MemoryCensus.take().groups.first { $0.members.contains { $0.pid == Int(root) } }
            f.check("  ... nor does a `.app/` path in the environment make it an app",
                    group?.category == .tools, "category \(group.map { "\($0.category)" } ?? "none")")
            var offered = false
            if case .confirm = MemoryStop.plan(target: t) { offered = true }
            f.check("  ... and a Stop on it is offered, still without sending anything", offered && f.alive(root), "plan(target:) confirms")
        } else { f.check("  ... nor an app", false, "program not found, or not contained") }
        f.end(root)
    } else { f.check("a title-rewriting program with text only in its environment", false, "fixture not found") }
}

// MARK: - the rule on its own, and a process that has ended

/// The rule that judges a command line, on what was read: an unreadable one is doubted; one identical to the
/// parent's is doubted for the first three seconds and not after (a subshell keeps its parent's for life, so
/// the doubt must end: a start at 3.1 s is not dodging anything, because every signal reads the live table and
/// the start time again); an empty one that was read is not unreadable.
@MainActor private func judgementCases(_ f: Fixtures) async {
    let j = GuardControl.commandLineJudgement
    f.check("a command line the kernel would not give is doubted", j(nil, "zsh", 99) != nil, "doubted at any age")
    f.check("one identical to its parent's, a moment after it started, is doubted", j("bash -c x", "bash -c x", 0.2) != nil, "age 0.2 s")
    f.check("  ... and at 2.9 s", j("bash -c x", "bash -c x", 2.9) != nil, "age 2.9 s")
    f.check("  ... but not at 3.1 s: the doubt ends", j("bash -c x", "bash -c x", 3.1) == nil, "age 3.1 s")
    f.check("a different one is believed at once", j("node server.js", "zsh", 0.1) == nil, "different from its parent's")
    f.check("one that was read and is empty is not unreadable", j("", "zsh", 10) == nil, "empty is readable")
    f.check("a process with no readable parent is judged on its own line", j("bash -c x", nil, 0.1) == nil, "no parent line to repeat")
}

/// A same-user process that has ended but not been collected (a zombie) has no readable arguments, ever. A
/// program that leaks one must still be stoppable: it is not doubted.
@MainActor private func zombieCase(_ f: Fixtures) async {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
        print("  not judged: no perl to make a zombie with")
        return
    }
    // the child exits at once; perl never waits for it, so it stays a zombie while its parent lives
    guard let root = await f.detach("exec /usr/bin/perl -e 'if (!fork) { exit } sleep 41; # \(f.marker)-z'", tag: "\(f.marker)-z") else {
        f.check("a program that leaks a zombie", false, "fixture not found")
        return
    }
    var zombie: Int32?
    for _ in 0..<40 where zombie == nil {
        zombie = ProcessTree.descendants(of: root).first { pid in
            f.run("/bin/ps", ["-o", "stat=", "-p", String(pid)]).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z")
        }
        if zombie == nil { try? await Task.sleep(for: .milliseconds(100)) }
    }
    if let zombie {
        f.check("a zombie under a program is not doubted", GuardControl.commandLineDoubt(pid: zombie) == nil, "an ended process is skipped")
        // perl lives in a system folder, so the census files it under macOS; the rule is judged on the reach itself
        if let identity = ProcessIdentity.of(pid: Int(root)) {
            let why = GuardControl.reachRefusal(listed: [identity], name: "Fixture program")
            f.check("  ... so a Stop on the program that leaked it is not refused for it", why == nil && f.alive(root), why ?? "the reach is computed, nothing signalled")
        }
    } else {
        print("  not judged: perl left no zombie to look at")
    }
    f.end(root)
}
