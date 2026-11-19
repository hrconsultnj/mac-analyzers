import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-stop-targets` cases for the rule "a lock guards automatic actions only; a person can stop
// anything they own". Every process here is a throwaway fixture the probe started detached and ends itself (see
// `Fixtures`); a fake `claude` process stands for a live coding session, so no real session is ever involved, and
// nothing is signalled unless every member of the program is the fixture or under it.

/// Every row of the tree, depth first.
private func everyRow(_ rows: [MonitorRow]) -> [MonitorRow] { rows.flatMap { [$0] + everyRow($0.children) } }

/// A fixture program whose top process is Node (not a shell, so what it starts is part of ITS program), named
/// `claude` so the app takes it for a live coding session. `source` is the JavaScript it runs; `tag` ends up in its command line.
@MainActor private func nodeProgram(_ f: Fixtures, source: String, tag: String) async -> Int32? {
    let node = "/opt/homebrew/bin/node"
    guard FileManager.default.isExecutableFile(atPath: node) else { return nil }
    let file = f.scratch.appending(path: "\(tag).js")
    try? source.write(to: file, atomically: true, encoding: .utf8)
    return await f.detach("exec -a claude \(node) '\(file.path)' \(tag)", tag: tag)
}

@MainActor func personStopCases(_ f: Fixtures) async {
    print("\na lock guards automatic actions only; a person can stop anything they own:")
    await unprotectedOwn(f)
    await protectedOwn(f)
    await protectedGroupMember(f)
    await emulatorUnderSession(f)
    await sessionAppearsMeanwhile(f)
    await ownChain(f)
    await notYours(f)
}

// MARK: - own process, nothing protecting it

@MainActor private func unprotectedOwn(_ f: Fixtures) async {
    guard let root = await f.detachNamed(nil, script: ": \(f.marker)-p1; sleep 70; :", tag: "\(f.marker)-p1") else {
        f.check("own program, nothing protecting it", false, "fixture not found"); return
    }
    defer { f.end(root) }
    guard let t = await f.program(root), f.contained(t, root: root) else {
        f.check("own program, nothing protecting it", false, "program not found, or not contained"); return
    }
    f.check("own program is stoppable by a person and carries no protection", t.isStoppableByPerson && t.protection == nil,
            "protection: \(t.protection ?? "none")")
    if case .confirm(let pending) = MemoryStop.plan(target: t, asPerson: true) {
        f.check("  ... the confirmation has no warning", pending.warning == nil, pending.detail)
        let report = await pending.run()
        f.check("  ... and Stop ends it", f.gone(root), report.message)
    } else { f.check("own program: the person's plan asks first", false, "refused") }
}

// MARK: - own process protected by a rule (a live coding session)

@MainActor private func protectedOwn(_ f: Fixtures) async {
    guard let root = await f.detachNamed("claude", script: ": \(f.marker)-p2; sleep 71; :", tag: "\(f.marker)-p2") else {
        f.check("own program of a live session", false, "fixture not found"); return
    }
    defer { f.end(root) }
    guard let t = await f.program(root), f.contained(t, root: root) else {
        f.check("own program of a live session", false, "program not found, or not contained"); return
    }
    f.check("locked for the automatic stops (isStoppable is false, a lock reason exists)", !t.isStoppable && t.lockedReason != nil,
            t.lockedReason ?? "NOT locked")
    var automatic = false
    if case .refused = MemoryStop.plan(target: t) { automatic = true }
    f.check("  ... the default plan (panel, notifications, guard) still refuses it", automatic && f.alive(root), "")
    let polite = await GuardControl.askProgramToStop(t.memberIdentities, name: t.label, grace: .seconds(1))
    f.check("  ... and the default polite stop still refuses it, sending nothing", polite.refusal != nil && f.alive(root),
            polite.refusal ?? "NOT refused")
    f.check("  ... the same program is stoppable by a person, with the reason", t.isStoppableByPerson && t.protection != nil,
            t.protection ?? "no reason")

    // Monitor's rows: Stop offered, the lock's reason kept as protection
    let rows = everyRow(MonitorTree.rows(census: MemoryCensus.take()))
    let row = rows.first { if case .stopProgram(let p) = $0.stop { p.id == t.id } else { false } }
    f.check("Monitor's row offers Stop on it and carries the protection", row?.stopVerb == "Stop" && row?.protection != nil,
            row?.protection ?? "no Stop row")

    guard case .confirm(let pending) = MemoryStop.plan(target: t, asPerson: true) else {
        f.check("the person's plan asks first", false, "refused"); return
    }
    f.check("the confirmation says first why it is normally protected and what may be lost",
            pending.warning?.contains("never stops") == true && pending.detail.hasPrefix(pending.warning ?? "?")
                && pending.warning?.contains("not saved") == true, pending.warning ?? "no warning")
    let caption = MemoryStop.reachText(of: t, asPerson: true)
    f.check("the sheet's caption for it says what would be reached, not that nothing would be stopped",
            caption?.contains("nothing was stopped") != true, caption ?? "reaches nothing more")
    print("       confirmation: \(pending.title) — \(pending.detail)")
    let report = await pending.run()
    f.check("Stop, once confirmed, ends it", f.gone(root), report.message)
}

// MARK: - a group whose parent is protected: its members are not locked

@MainActor private func protectedGroupMember(_ f: Fixtures) async {
    // the session root with a child program under it: a group of one program with members
    let source = "const { spawn } = require('child_process')\nspawn('sleep', ['72'])\nspawn('sleep', ['73'])\nsetTimeout(() => {}, 76000)\n"
    guard let root = await nodeProgram(f, source: source, tag: "\(f.marker)-p3") else {
        f.check("group of a protected parent", false, "fixture not found"); return
    }
    defer { f.end(root) }
    guard let t = await f.program(root), f.contained(t, root: root) else {
        f.check("group of a protected parent", false, "program not found, or not contained"); return
    }
    let census = MemoryCensus.take()
    guard let group = census.groups.first(where: { $0.programs.contains { $0.id == t.id } }) else {
        f.check("group of a protected parent", false, "group not found"); return
    }
    let rows = MonitorTree.rows(census: census)
    guard let groupRow = rows.first(where: { $0.id == "group:\(group.id)" }) else {
        f.check("group of a protected parent", false, "row not found"); return
    }
    var offered = false
    if case .choosePrograms(_, let programs) = groupRow.stop { offered = programs.contains { $0.id == t.id && $0.isStoppableByPerson } }
    f.check("the group row offers Stop although its parent is protected", offered && groupRow.protection != nil,
            groupRow.protection ?? "no protection said")
    let members = everyRow(groupRow.children).filter { $0.kind == .process }
    print("       (group \(group.name): \(groupRow.children.count) program rows; program \(t.id) has \(t.members.count) members; process rows \(members.count))")
    let childRows = members.filter { $0.pid.map { Int32($0) != root } ?? false }
    let allOffer = !childRows.isEmpty && childRows.allSatisfy { if case .stopProcess = $0.stop { true } else { false } }
    f.check("every member is stoppable too (\(childRows.count) member rows), never locked because the group is", allOffer,
            childRows.map { String(describing: $0.stop) }.joined(separator: ", "))

    // one member, stopped on its own: the default refuses (a session is above it), the person's choice does not
    if let child = childRows.first, case .stopProcess(let process, let identity) = child.stop {
        var refused = false
        if case .refused = GuardControl.stopProcess(process, identity: identity) { refused = true }
        f.check("  (the default single stop still refuses a process under a live session)", refused && f.alive(Int32(process.pid)), "")
        let result = GuardControl.stopProcess(process, identity: identity, overridingProtection: true)
        try? await Task.sleep(for: .milliseconds(500))
        f.check("  ... and the person's choice stops that one member, leaving the rest", result == .stopped && f.gone(Int32(process.pid)) && f.alive(root),
                "\(result)")
    }
}

// MARK: - the Android emulator case

@MainActor private func emulatorUnderSession(_ f: Fixtures) async {
    // an emulator the person started inside a coding session's terminal, which does not exit at the polite request
    let source = "const { spawn } = require('child_process')\nspawn('/opt/homebrew/bin/bash', ['-c', 'trap \\\"\\\" TERM; sleep 74 & wait'], { argv0: 'qemu-system-aarch64-headless' })\nsetTimeout(() => {}, 77000)\n"
    guard let root = await nodeProgram(f, source: source, tag: "\(f.marker)-p4") else {
        f.check("an emulator under a live session", false, "fixture not found"); return
    }
    defer { f.end(root) }
    let qemu = await f.find("qemu-system-aarch64-headless -c", detachedOnly: false)
    guard let t = await f.program(root), f.contained(t, root: root), let qemu else {
        f.check("an emulator under a live session", false, "program or emulator not found"); return
    }
    f.check("  (the emulator is in the program, named for what it is)", t.members.contains { $0.pid == Int(qemu) }, "pid \(qemu)")
    guard case .confirm(let pending) = MemoryStop.plan(target: t, asPerson: true) else {
        f.check("the emulator can be stopped by the person who started it", false, "refused"); return
    }
    let first = await pending.run()
    f.check("the polite stop goes first and the emulator, ignoring it, is still running", first.force != nil && f.alive(qemu),
            first.message)
    guard let force = first.force else { return }
    print("       second question: \(force.title) — \(force.detail)")
    f.check("the Force Stop question restates what protects the program", force.detail.hasPrefix(pending.warning ?? "?"), "")
    let second = await force.run()
    f.check("Force Stop, once confirmed, ends the emulator and everything it started",
            f.gone(qemu) && f.gone(root) && ProcessTree.descendants(of: root).isEmpty, second.message)
}

// MARK: - what stays out of reach

@MainActor private func notYours(_ f: Fixtures) async {
    // root's own process: no Stop is offered, and a stop sent anyway is refused before anything is signalled
    let census = MemoryCensus.take()
    let rows = MonitorTree.rows(census: census)
    let system = rows.filter { $0.category == .system }
    f.check("every macOS service row is unstoppable (\(system.count) rows)",
            !system.isEmpty && system.allSatisfy { $0.stopVerb == nil && $0.lockedReason != nil }, "")
    if let launchd = LiveStats.process(pid: 1), let identity = launchd.identity ?? ProcessIdentity.of(pid: 1) {
        let result = GuardControl.stopProcess(launchd, identity: identity, overridingProtection: true)
        var refused = false
        if case .refused(let why) = result { refused = why.contains("another account") }
        f.check("a root process is refused even when the person chose it (launchd, nothing signalled)", refused, "\(result)")
    }
    let others = everyRow(rows).filter { row in
        if case .unavailable(let why) = row.stop { return why.contains("another account") || why.contains("Runs under another account") }
        return false
    }
    f.check("another account's rows say why in words (\(others.count) of them)", others.allSatisfy { $0.stopVerb == nil }, "")
    let shell = await f.shellFixture("sleep 75 &\nwait\n", tag: "\(f.marker)-p5")
    if let shell, let t = await f.program(shell) {
        f.check("a terminal session is not stoppable, with the reason in words", !t.isStoppableByPerson && t.personRefusal?.contains("terminal session") == true,
                t.personRefusal ?? "stoppable")
        var refused = false
        if case .refused = MemoryStop.plan(target: t, asPerson: true) { refused = true }
        f.check("  ... and the person's plan refuses it", refused && f.alive(shell), "")
    } else { f.check("a terminal session is not stoppable", false, "fixture not found") }
    if let shell { f.end(shell) }
}

// MARK: - a session that starts while the person decides

@MainActor private func sessionAppearsMeanwhile(_ f: Fixtures) async {
    // a plain program; four seconds after the dialog opens a fake session starts under it (its own shell, its own command line)
    let late = ": \(f.marker)-p6; \(f.shell) -c \"sleep 4; exec -a \(f.sessionExe) \(f.shell) -c \\\": \(f.marker)-p6b; sleep 76; :\\\"\" & while :; do sleep 1; done"
    guard let root = await f.detachNamed(nil, script: late, tag: "\(f.marker)-p6"), let t = await f.program(root), f.contained(t, root: root) else {
        f.check("a session that starts while the person decides", false, "fixture not found"); return
    }
    defer { f.end(root) }
    guard case .confirm(let pending) = MemoryStop.plan(target: t, asPerson: true) else {
        f.check("a session that starts while the person decides", false, "refused"); return
    }
    f.check("  (the dialog opened with no session to name)", pending.warning == nil, pending.warning ?? "none")
    try? await Task.sleep(for: .seconds(6))
    let report = await pending.run()
    f.check("confirming then sends nothing and says a session appeared", f.alive(root) && report.message.contains("started in"), report.message)
}

// MARK: - Sparehold itself

@MainActor private func ownChain(_ f: Fixtures) async {
    guard let live = LiveStats.process(pid: Int(getpid())), let identity = live.identity ?? ProcessIdentity.of(pid: Int(getpid())) else {
        f.check("Sparehold' own process", false, "not found"); return
    }
    for override in [false, true] {
        let result = GuardControl.stopProcess(live, identity: identity, overridingProtection: override)
        var refused = false
        if case .refused(let why) = result { refused = why.contains("Sparehold itself") }
        f.check("a single stop of Sparehold' own process is refused (override \(override))", refused, "\(result)")
    }
    let census = MemoryCensus.take()
    if let mine = census.groups.flatMap(\.programs).first(where: { $0.members.contains { $0.pid == Int(getpid()) } }) {
        f.check("its program has no Stop, and the row says why", mine.personRefusal?.contains("Sparehold itself") == true, mine.personRefusal ?? "stoppable")
    }
    let own = everyRow(MonitorTree.rows(census: census)).first { $0.kind == .process && $0.pid == Int(getpid()) }
    if let own {
        f.check("its process row is unavailable", own.stopVerb == nil && own.lockedReason?.contains("Sparehold itself") == true, own.lockedReason ?? "offers Stop")
    }
}
