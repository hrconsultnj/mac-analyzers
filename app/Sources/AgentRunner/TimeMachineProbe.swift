import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-tm` judges itself. It runs the REAL `tm-reclaim.sh` in a throwaway HOME with stand-in
// `tmutil`, `sudo` and `df` that only log what they were asked (nothing real is read or changed, no snapshot,
// backup or permission is ever touched), and checks that what it printed is what the Time Machine screen reads:
// the banner is a banner, the block is found whole in its own log, the snapshots become rows by day with the
// system's own kept apart, an apply is read as Thinned with the free space before and after, a refused thinning
// is read as needing permission. It also proves what the app SENDS (preview and apply arguments, with and without
// the backup) against a stand-in engine, and what the permission prompt would run, as text that is only printed.
// Exit 1 when anything differs.

@MainActor func probeTimeMachine() async -> Never {
    let fm = FileManager.default
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    var script: URL?
    for _ in 0..<8 {
        let candidate = dir.appending(path: "storage-analyzer/tm-reclaim.sh")
        if fm.fileExists(atPath: candidate.path) { script = candidate; break }
        dir = dir.deletingLastPathComponent()
    }
    guard let script else { print("FAIL: tm-reclaim.sh was not found in any folder above \(CommandLine.arguments[0]), so this probe did not run"); exit(1) }

    let root = ProbeScratch.folder("ma-probe-tm")
    let home = root.appending(path: "home"), stubs = root.appending(path: "stubs")
    for folder in [home, stubs] { try? fm.createDirectory(at: folder, withIntermediateDirectories: true) }
    var failures = 0, cases = 0
    func expect(_ ok: Bool, _ what: @autoclosure () -> String) { cases += 1; if !ok { failures += 1; print("FAIL  \(what())") } }

    // stand-ins: tmutil lists three snapshots (two TM, one macOS) and logs; sudo logs and obeys a deny file; df counts
    let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyy-MM-dd-HHmmss"
    let now = Date()
    let today = stamp.string(from: now.addingTimeInterval(-3_600)), earlier = stamp.string(from: now.addingTimeInterval(-3 * 86_400))
    let calls = root.appending(path: "calls.log"), deny = root.appending(path: "deny"), counter = root.appending(path: "df-count")
    func write(_ name: String, _ body: String) { let url = stubs.appending(path: name); try? body.write(to: url, atomically: true, encoding: .utf8); chmod(url.path, 0o755) }
    write("tmutil", "#!/bin/bash\necho \"tmutil $*\" >> \"\(calls.path)\"\nif [[ \"$1\" == listlocalsnapshots ]]; then\n  echo com.apple.TimeMachine.\(today).local\n  echo com.apple.TimeMachine.\(earlier).local\n  echo com.apple.os.update-AB12\nfi\n")
    write("sudo", "#!/bin/bash\necho \"sudo $*\" >> \"\(calls.path)\"\n[[ -f \"\(deny.path)\" ]] && exit 1\nexit 0\n")
    write("df", "#!/bin/bash\nn=$(cat \"\(counter.path)\" 2>/dev/null || echo 0); echo $((n + 1)) > \"\(counter.path)\"\nif [[ $n -eq 0 ]]; then a=51Gi; else a=60Gi; fi\nprintf 'Filesystem Size Used Avail Capacity Mounted on\\n/dev/x 460Gi 400Gi %s 89%% /System/Volumes/Data\\n' $a\n")

    func run(_ arguments: [String]) -> (lines: [String], status: Int32) {
        try? fm.removeItem(at: counter)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.environment = ["HOME": home.path, "PATH": "\(stubs.path):/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return ([], -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return (text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, process.terminationStatus)
    }
    func calledLines() -> [String] { ((try? String(contentsOf: calls, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
    let log = home.appending(path: "mac-analyzers/reports/storage/tm-reclaim.log")

    // the preview
    let preview = run(["--dry-run"])
    let banner = preview.lines.compactMap { RunMatcher.banner(in: $0) }.first
    expect(banner?.hasPrefix("tm-reclaim | DRY RUN | backup=on | ") == true, "the preview has a banner: \(banner ?? "none")")
    let review = TimeMachineReview.build(lines: preview.lines, now: now)
    expect(review.thinnable == 2, "two local snapshots can be thinned, got \(review.thinnable)")
    expect(review.rows.rows.filter { !$0.isChoosable }.map(\.group) == [Names.Temp.managedByMacOS], "macOS's own snapshot is kept apart: \(review.rows.rows.map { "\($0.group ?? "-"):\($0.title)" })")
    expect(Set(review.rows.rows.filter(\.isChoosable).compactMap(\.group)).contains("Today") && review.rows.rows.filter(\.isChoosable).count == 2, "snapshots are grouped by day, today first: \(review.rows.rows.compactMap(\.group))")
    expect(review.freeBefore == "51Gi", "free space before is read: \(review.freeBefore ?? "nil")")
    if let banner, case .block(let block) = WholeRun.find(banner: banner, in: log) {
        expect(TimeMachineReview.build(lines: block.lines, now: now).thinnable == 2, "the block found in the log by its banner gives the same snapshots")
    } else { expect(false, "the block was not found in tm-reclaim.log by its banner") }
    expect(calledLines().allSatisfy { $0.hasPrefix("tmutil listlocalsnapshots") } && calledLines().count == 1, "a preview only listed the snapshots: \(calledLines())")

    // an apply that worked
    try? fm.removeItem(at: calls)
    let applied = run(["--apply", "--no-backup"])
    let after = TimeMachineReview.build(lines: applied.lines, results: true, now: now)
    expect(applied.status == 0 && after.freeAfter == "60Gi" && after.rows.facts.first == "free space 51Gi → 60Gi", "an apply is read with the free space before and after: \(after.rows.facts)")
    expect(after.rows.rows.filter(\.isChoosable).allSatisfy { $0.valueText == "Thinned" }, "each snapshot reads Thinned")
    expect(calledLines().filter { $0.hasPrefix("sudo") } == ["sudo -n /usr/bin/tmutil thinlocalsnapshots / 999999999999 4"], "exactly one whitelisted thin call: \(calledLines())")
    expect(!calledLines().contains { $0.contains("startbackup") }, "--no-backup starts no backup")

    // an apply that was refused
    try? fm.removeItem(at: calls); try? "x".write(to: deny, atomically: true, encoding: .utf8)
    let refused = run(["--apply"])
    let denied = TimeMachineReview.build(lines: refused.lines, results: true, now: now)
    expect(refused.status == 3 && denied.needsPermission, "a refused thinning exits 3 and is read as needing permission (exit \(refused.status))")
    expect(denied.rows.rows.filter(\.isChoosable).allSatisfy { $0.valueText == "Couldn't Thin" }, "each snapshot reads Couldn't Thin")
    expect(!calledLines().contains { $0.contains("startbackup") }, "no backup starts when thinning was refused")
    try? fm.removeItem(at: deny)

    // what the app sends, through the real job store, to a stand-in engine
    let engine = root.appending(path: "engine.sh")
    try? "#!/bin/bash\nmode=APPLY; [[ \"$*\" == *--dry-run* ]] && mode=\"DRY RUN\"\necho \"tm-reclaim | $mode | stand-in | $(date '+%Y-%m-%d %H:%M:%S')\"\necho \"args: $*\"\n".write(to: engine, atomically: true, encoding: .utf8)
    chmod(engine.path, 0o755)
    let store = JobStore(ledger: JobLedger(url: root.appending(path: "jobs.jsonl")))
    store.scriptOverride = engine
    store.outcomeOverride = { _, _ in JobOutcome(parsed: .none, run: nil, match: .exact) }
    func wait(_ job: Job) async { while !job.state.isFinished { try? await Task.sleep(for: .milliseconds(20)) } }
    for backup in [true, false] {
        let job = store.enqueue(JobRequest(kind: .tmReclaim, intent: .preview, options: JobOptions(startBackup: backup)), trigger: .user)
        await wait(job)
        expect(job.lines.contains("args: --dry-run"), "a preview sends --dry-run: \(job.lines)")
        let apply = store.apply(from: job, approved: .everything)
        await wait(apply)
        let sent = apply.lines.first { $0.hasPrefix("args:") } ?? ""
        expect(sent == (backup ? "args: --apply" : "args: --apply --no-backup"), "an apply \(backup ? "with" : "without") the backup sends \"\(sent)\"")
    }
    expect(StorageSetting.options(kind: .tmReclaim, banner: "tm-reclaim | DRY RUN | backup=off | 2026-11-11 10:00:00").startBackup == false
           && StorageSetting.options(kind: .tmReclaim, banner: "tm-reclaim | APPLY | backup=on | 2026-11-11 10:00:00").startBackup, "the backup setting is read from the banner")

    // ---- the permission: every byte that reaches root, and where it comes from ----
    let user = "alice"
    guard let rootCommand = TimeMachinePermission.installRootCommand(user: user),
          let prompt = TimeMachinePermission.installAppleScript(user: user) else {
        print("FAIL  no root command was built for a valid account name"); exit(1)
    }
    print("The root command the administrator prompt would run:\n  \(rootCommand)")
    print("The AppleScript that shows it:\n  \(prompt)")
    print("The removal:\n  \(TimeMachinePermission.removeRootCommand)\n")
    let allowedPrefixes = ["/usr/bin/", "/usr/sbin/", "/bin/", "/etc/sudoers.d/", "/private/var/root/"]
    func pathsIn(_ command: String) -> [String] {
        command.split(whereSeparator: { " ;{}".contains($0) }).map(String.init).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }.filter { $0.hasPrefix("/") && $0 != "/" }   // a lone "/" is the volume argument inside the quoted rule text
    }
    for command in [rootCommand, TimeMachinePermission.removeRootCommand] {
        let outside = pathsIn(command).filter { path in !allowedPrefixes.contains { path.hasPrefix($0) } }
        expect(outside.isEmpty, "every path in the root command is a system path or root's own folder; outside: \(outside)")
        expect(!command.contains("$") && !command.contains("`"), "no variable, substitution or backtick in the root command")
        expect(!command.contains(NSHomeDirectory()) && !command.contains(".app/") && !command.contains(".sh"), "no file under the home folder, in an app bundle, and no script of ours is named")
    }
    var unquoted = rootCommand
    while let open = unquoted.firstIndex(of: "'"), let close = unquoted[unquoted.index(after: open)...].firstIndex(of: "'") { unquoted.removeSubrange(open...close) }
    expect(!unquoted.contains(user), "the user's name appears only inside single quotes")
    expect(prompt.contains("with prompt \"Mac Analyzers wants to allow one command") && prompt.hasSuffix("with administrator privileges") && prompt.contains("for the account alice"),
           "the dialog says what is allowed, in the app's words")
    expect(TimeMachinePermission.removeAppleScript.contains("with prompt \"Mac Analyzers wants to remove the permission") && TimeMachinePermission.removeAppleScript.contains("\"/bin/rm -f /etc/sudoers.d/tmutil-thin\""),
           "the removal is one fixed command behind its own prompt")
    // account names
    for bad in ["", "root", "ALL", "all", "a b", "a'b", "a\"b", "a\nb", "a%b", "%admin", "#0", "a#b", "a,b", "!a", "-a", ".a", "a;b", "a$b", "a`b", String(repeating: "a", count: 65)] {
        expect(!TimeMachinePermission.isValidUser(bad) && TimeMachinePermission.installRootCommand(user: bad) == nil && TimeMachinePermission.installAppleScript(user: bad) == nil,
               "a rule is never written for the name \"\(bad.replacingOccurrences(of: "\n", with: "\\n"))\"")
    }
    expect(["alice", "helder.r-2", "_svc", "A1"].allSatisfy(TimeMachinePermission.isValidUser), "ordinary account names are accepted")
    // the constant is the template's text, and the engine runs exactly that command
    let repo = script.deletingLastPathComponent().deletingLastPathComponent()
    let template = (try? String(contentsOf: repo.appending(path: "storage-analyzer/sudoers.d/tmutil-thin"), encoding: .utf8)) ?? ""
    let active = template.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    expect(active.count == 1 && active[0].replacingOccurrences(of: "__USERNAME__", with: user) == TimeMachinePermission.ruleLine(for: user),
           "the repository's template is the app's constant, word for word: \(active)")
    expect(!(active.first ?? "").contains("*"), "the rule has no wildcard: the arguments must match exactly")
    for name in ["tm-reclaim.sh", "storage-auto-clean.sh"] {
        let text = (try? String(contentsOf: repo.appending(path: "storage-analyzer/\(name)"), encoding: .utf8)) ?? ""
        let uses = text.components(separatedBy: "\n").filter { $0.contains("/usr/bin/tmutil thinlocalsnapshots") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        expect(!uses.isEmpty && uses.allSatisfy { $0.contains(TimeMachinePermission.thinCommand) }, "\(name) runs exactly the allowed command line: \(uses)")
    }
    // a hostile clone: a template that grants ALL, a script that writes a marker, fakes first on PATH. Run the
    // command with its system paths pointed at stand-ins (never the real /etc or visudo): neither file is read or run.
    let hostile = root.appending(path: "hostile-clone"), fakeBin = hostile.appending(path: "bin")
    for folder in ["storage-analyzer/sudoers.d", "bin", "../etc", "../rootdir"] { try? fm.createDirectory(at: hostile.appending(path: folder), withIntermediateDirectories: true) }
    let marker = hostile.appending(path: "MARKER")
    try? "alice ALL=(ALL) NOPASSWD: ALL\n".write(to: hostile.appending(path: "storage-analyzer/sudoers.d/tmutil-thin"), atomically: true, encoding: .utf8)
    try? "#!/bin/bash\ntouch \"\(marker.path)\"\n".write(to: hostile.appending(path: "storage-analyzer/storage-manage-agents.sh"), atomically: true, encoding: .utf8)
    for fake in ["visudo", "install", "printf", "rm", "sed", "mktemp", "sudo"] {
        let url = fakeBin.appending(path: fake)
        try? "#!/bin/bash\ntouch \"\(marker.path)\"\n".write(to: url, atomically: true, encoding: .utf8); chmod(url.path, 0o755)
    }
    let etc = root.appending(path: "etc"), rootDir = root.appending(path: "rootdir"), standIns = root.appending(path: "standins")
    for folder in [etc, rootDir, standIns] { try? fm.createDirectory(at: folder, withIntermediateDirectories: true) }
    let visudoLog = root.appending(path: "visudo.log")
    try? "#!/bin/bash\necho \"visudo $*\" >> \"\(visudoLog.path)\"\nexit 0\n".write(to: standIns.appending(path: "visudo"), atomically: true, encoding: .utf8)
    try? "#!/bin/bash\nlast=\"${@: -1}\"; prev=\"${@: -2:1}\"; cp \"$prev\" \"$last\"\n".write(to: standIns.appending(path: "install"), atomically: true, encoding: .utf8)
    for stub in ["visudo", "install"] { chmod(standIns.appending(path: stub).path, 0o755) }
    func simulated(_ command: String) -> String {
        command.replacingOccurrences(of: "/usr/sbin/visudo", with: standIns.appending(path: "visudo").path)
            .replacingOccurrences(of: "/usr/bin/install", with: standIns.appending(path: "install").path)
            .replacingOccurrences(of: "/private/var/root/", with: rootDir.path + "/")
            .replacingOccurrences(of: "/etc/sudoers.d/", with: etc.path + "/")
    }
    func runSimulated(_ command: String) -> Int32 {
        let simulation = simulated(command)
        // before running anything: no real system file named any more
        let real = pathsIn(simulation).filter { $0.hasPrefix("/etc/") || $0.hasPrefix("/private/var/root") || $0.hasSuffix("/visudo") && !$0.hasPrefix(standIns.path) }
        guard real.isEmpty else { print("FAIL  the simulation would touch a real path: \(real)"); return 99 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", simulation]
        process.currentDirectoryURL = hostile
        process.environment = ["PATH": "\(fakeBin.path):/usr/bin:/bin", "HOME": hostile.path]
        process.standardOutput = Pipe(); process.standardError = Pipe()
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
    let status = runSimulated(rootCommand)
    let installed = (try? String(contentsOf: etc.appending(path: "tmutil-thin"), encoding: .utf8)) ?? ""
    expect(status == 0 && installed == "\(TimeMachinePermission.ruleLine(for: user) ?? "")\n", "run in a hostile clone, what is installed is the app's own line and nothing else: \(installed.debugDescription)")
    expect(!installed.contains("ALL=(ALL)") && !fm.fileExists(atPath: marker.path), "the clone's template is not read and none of its programs run")
    expect(((try? String(contentsOf: visudoLog, encoding: .utf8)) ?? "").contains("visudo -cf") && ((try? String(contentsOf: visudoLog, encoding: .utf8)) ?? "").contains("visudo -c\n"), "visudo checked the file, then the live configuration")
    expect(!fm.fileExists(atPath: rootDir.appending(path: ".mac-analyzers-tmutil-thin").path), "the scratch file is gone afterwards")
    expect(runSimulated(TimeMachinePermission.removeRootCommand) == 0 && !fm.fileExists(atPath: etc.appending(path: "tmutil-thin").path) && !fm.fileExists(atPath: marker.path), "the removal removes the rule and nothing else")
    // a failing check stops the install and leaves nothing behind
    try? "#!/bin/bash\nexit 1\n".write(to: standIns.appending(path: "visudo"), atomically: true, encoding: .utf8)
    let refusedStatus = runSimulated(rootCommand)
    expect(refusedStatus != 0 && !fm.fileExists(atPath: etc.appending(path: "tmutil-thin").path) && !fm.fileExists(atPath: rootDir.appending(path: ".mac-analyzers-tmutil-thin").path),
           "when visudo refuses the file nothing is installed and the scratch file is removed (status \(refusedStatus))")
    // is it allowed: sudo is ASKED, as this person, and only listed; a stand-in sudo answers
    let askLog = root.appending(path: "ask.log")
    for (code, expected) in [(0, true), (1, false)] {
        try? "#!/bin/bash\necho \"$*\" >> \"\(askLog.path)\"\nexit \(code)\n".write(to: standIns.appending(path: "sudo"), atomically: true, encoding: .utf8)
        chmod(standIns.appending(path: "sudo").path, 0o755)
        let answer = await TimeMachinePermission.isAllowed(sudo: standIns.appending(path: "sudo").path)
        expect(answer == expected, "sudo answering \(code) means \(expected ? "allowed" : "not allowed"), so a rule file left by another version does not read as allowed")
    }
    expect(((try? String(contentsOf: askLog, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }.allSatisfy { $0 == "-n -l /usr/bin/tmutil thinlocalsnapshots / 999999999999 4" },
           "it only asks sudo to LIST the command, with no password prompt")

    print("\(cases) checks, \(failures == 0 ? "the script's output, what is sent and what the prompt runs all agree" : "\(failures) FAILED")")
    exit(failures == 0 ? 0 : 1)
}
