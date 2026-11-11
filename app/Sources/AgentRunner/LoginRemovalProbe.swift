import Foundation
import os
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-login-removal`: the rules for removing login-item
// leftovers through the job kernel, judged by itself (exit 1 when one breaks) so
// it can run in the gate. Test scripts and a temporary job index only; it never
// reaches the real engine or the real LaunchAgents folder.

@MainActor func probeLoginRemoval() async -> Never {
    let dir = ProbeScratch.folder("ma-probe-login")      // removed when the probe ends, however it ends
    let echo = dir.appending(path: "audit-echo.sh")
    try? """
    #!/bin/bash
    echo "login-items-audit  |  DRY RUN  |  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "args: $*"
    if [ "$2" = "--only-paths" ]; then echo "list: $(tr '\\n' ',' < "$3")"; fi
    """.write(to: echo, atomically: true, encoding: .utf8)
    chmod(echo.path, 0o755)

    var offset: TimeInterval = 0
    let found = OSAllocatedUnfairLock(initialState: true)
    let store = JobStore(ledger: JobLedger(url: dir.appending(path: "jobs.jsonl")),
                         clock: { Date().addingTimeInterval(offset) })
    store.scriptOverride = echo
    store.outcomeOverride = { _, _ in
        JobOutcome(parsed: .none, run: nil, match: found.withLock { $0 } ? .exact : .newestFallback("fixture"))
    }

    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "PASS  " : "FAIL  ") + name + (detail.isEmpty ? "" : ": " + detail))
        if !ok { failures += 1 }
    }
    func finished(_ job: Job) async { while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(30)) } }
    func idle() async { while store.running != nil || !store.queued.isEmpty { try? await Task.sleep(for: .milliseconds(30)) } }
    func refused(_ job: Job) -> Bool { if case .failed = job.state { true } else { false } }
    func audit() async -> Job {
        let job = store.enqueue(JobRequest(kind: .loginItems, intent: .preview), trigger: .user)
        await finished(job)
        await idle()
        return job
    }
    func list(_ job: Job) -> String? {
        job.lines.first { $0.hasPrefix("list:") }.map { String($0.dropFirst("list: ".count)) }
    }

    let plists = ["/L/a.plist", "/L/b.plist"]
    let direct = store.enqueue(JobRequest(kind: .loginItems, intent: .apply), trigger: .user)
    check("an apply built without an audit is refused", refused(direct))

    let one = store.apply(from: await audit(), approved: ApprovedSet(approvable: plists, deselected: ["/L/b.plist"]))
    await finished(one)
    check("one of two ticked sends only that path", list(one) == "/L/a.plist", list(one) ?? "no list")

    let all = store.apply(from: await audit(), approved: ApprovedSet(approvable: plists, deselected: []))
    await finished(all)
    check("nothing deselected sends every reviewed path", list(all) == "/L/a.plist,/L/b.plist", list(all) ?? "no list")

    let late = store.apply(from: await audit(), approved: ApprovedSet(approvable: ["/L/a.plist"], deselected: []))
    await finished(late)
    check("an item that appeared after the review is not in the list", list(late) == "/L/a.plist", list(late) ?? "no list")

    let none = store.apply(from: await audit(), approved: ApprovedSet(approvable: plists, deselected: Set(plists)))
    await finished(none)
    check("everything deselected sends an empty list, never a bare apply",
          list(none) == "" && none.lines.contains { $0.contains("--only-paths") }, none.lines.joined(separator: " | "))

    let unrestricted = store.apply(from: await audit(), approved: .everything)
    await finished(unrestricted)
    check("an unrestricted approval is refused", refused(unrestricted))

    let twice = await audit()
    let first = store.apply(from: twice, approved: ApprovedSet(approvable: plists, deselected: []))
    await finished(first)
    await idle()
    let second = store.apply(from: twice, approved: ApprovedSet(approvable: plists, deselected: []))
    check("an audit can be applied once", refused(second))

    let old = await audit()
    offset = JobStore.reviewWindow + 60
    check("an audit older than the review window is refused",
          refused(store.apply(from: old, approved: ApprovedSet(approvable: plists, deselected: []))))
    offset = 0

    let dismissed = await audit()
    store.dismiss(dismissed)
    check("a discarded audit is refused",
          refused(store.apply(from: dismissed, approved: ApprovedSet(approvable: plists, deselected: []))))

    // the screen's own rule: what a row action sends is exactly what its confirmation names
    func leftover(_ name: String, scope: StartupItem.Scope = .user) -> StartupItem {
        StartupItem(id: "agent|\(scope.rawValue)|/L/\(name).plist", kind: .launchAgent, scope: scope, label: "com.zz.\(name)",
                    plistPath: "/L/\(name).plist", targetPath: "/gone/\(name)", finding: .leftover, state: .notLoaded,
                    reason: .targetMissing, fixCommand: nil, name: name, owner: "zz", ownerSource: .label, appPath: nil)
    }
    let a = leftover("a"), b = leftover("b"), system = leftover("sys", scope: .system)
    check("a selection can be narrowed to (the kernel takes a list for login items)", StartupRemoval.canNarrowToSelection)
    check("a row's Remove scope is that row alone",
          StartupRemoval.scope(chosen: [a], removable: [a, b]).map(\.name) == ["a"])
    check("a system item is never in a Remove scope", StartupRemoval.scope(chosen: [system], removable: [a, b]).isEmpty)
    let rowScope = StartupRemoval.scope(chosen: [a], removable: [a, b])
    let rowApproval = StartupRemoval.approval(for: rowScope, removable: [a, b])
    check("the approval holds exactly the chosen row", rowApproval.approved == ["/L/a.plist"], rowApproval.approved.joined(separator: ","))
    let rowApply = store.apply(from: await audit(), approved: rowApproval)
    await finished(rowApply)
    check("the list sent to the script is the confirmed row", list(rowApply) == "/L/a.plist", list(rowApply) ?? "no list")
    let allScope = StartupRemoval.scopeAll(removable: [a, b])   // the toolbar's Remove Leftovers, the screen's own call
    let allApproval = StartupRemoval.approval(for: allScope, removable: [a, b])
    check("Remove Leftovers sends every removable item and nothing else",
          allScope.map(\.name) == ["a", "b"] && allApproval.approved == ["/L/a.plist", "/L/b.plist"])
    let onlyOne = StartupRemoval.approval(for: StartupRemoval.scope(chosen: [a], removable: [a]), removable: [a])
    let onlyApply = store.apply(from: await audit(), approved: onlyOne)
    await finished(onlyApply)
    check("with one removable item the list is still sent", list(onlyApply) == "/L/a.plist", list(onlyApply) ?? "no list")

    found.withLock { $0 = false }
    let fallback = await audit()
    check("an audit whose own block was not found is refused",
          refused(store.apply(from: fallback, approved: ApprovedSet(approvable: plists, deselected: []))))

    print(failures == 0 ? "all login-removal rules hold" : "\(failures) login-removal rule(s) broken")
    exit(failures == 0 ? 0 : 1)
}
