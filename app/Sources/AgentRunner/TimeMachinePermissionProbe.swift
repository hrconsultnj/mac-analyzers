import Foundation
@_spi(TestSupport) import AnalyzersKit

// The permission half of `agent-runner --probe-tm`: every byte that reaches root and where it comes from, the
// environment the root shell starts with, how "allowed" is read from sudo, and the backup-disk question. Only
// stand-ins run (a `visudo` and an `install` that write into temp folders, a `sudo` and a `tmutil` that print what the
// case says); the real administrator prompt, `visudo`, `install`, `rm` in /etc and `tmutil` verbs are never run.

@MainActor func probeTimeMachinePermission(root: URL, repo: URL, expect: (Bool, String) -> Void) async {
    let fm = FileManager.default
    let uid: UInt32 = 501

    // ---- the root command: what it is made of ----
    guard let rootCommand = TimeMachinePermission.installRootCommand(uid: uid), let installScript = TimeMachinePermission.installAppleScript(uid: uid),
          let removeCommand = TimeMachinePermission.removeRootCommand(uid: uid), let removeScript = TimeMachinePermission.removeAppleScript(uid: uid) else {
        expect(false, "a valid user ID gets an install and a removal command"); return
    }
    let ruleFile = TimeMachinePermission.ruleFile(uid: uid)
    print("The root command the administrator prompt would run:\n  \(rootCommand)")
    print("The AppleScript that shows it:\n  \(installScript)")
    print("The removal:\n  \(removeCommand)\n")
    let allowedPrefixes = ["/usr/bin/", "/usr/sbin/", "/bin/", "/etc/sudoers.d/", "/private/var/root/"]
    func pathsIn(_ command: String) -> [String] {
        command.split(whereSeparator: { " ;{}".contains($0) }).map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
            .filter { $0.hasPrefix("/") && $0 != "/" }   // a lone "/" is the volume argument inside the quoted rule text
    }
    for command in [rootCommand, removeCommand] {
        let outside = pathsIn(command).filter { path in !allowedPrefixes.contains { path.hasPrefix($0) } }
        expect(outside.isEmpty, "every path in the root command is a system path or root's own folder; outside: \(outside)")
        expect(!command.contains("$") && !command.contains("`"), "no variable, substitution or backtick in the root command")
        expect(!command.contains(NSHomeDirectory()) && !command.contains(".app/") && !command.contains(".sh"), "no file under the home folder, in an app bundle, and no script of ours is named")
    }
    // the only byte that varies is a run of digits: the account's numeric user ID, inside single quotes
    for other in [1, 99_999, UInt32.max] {
        guard let command = TimeMachinePermission.installRootCommand(uid: other), let removal = TimeMachinePermission.removeRootCommand(uid: other) else { expect(false, "user ID \(other) gets commands"); continue }
        let varied = command.replacingOccurrences(of: "#\(other) ", with: "#\(uid) ").replacingOccurrences(of: "tmutil-thin-\(other)", with: "tmutil-thin-\(uid)")
        expect(varied == rootCommand, "the command for user ID \(other) differs from the one for \(uid) only in the digits")
        expect(removal.replacingOccurrences(of: "tmutil-thin-\(other)", with: "tmutil-thin-\(uid)") == removeCommand, "the removal for user ID \(other) differs only in the digits")
    }
    // user ID 0 (the app running as root): no rule, no removal, and why
    expect(TimeMachinePermission.installRootCommand(uid: 0) == nil && TimeMachinePermission.installAppleScript(uid: 0) == nil
           && TimeMachinePermission.removeRootCommand(uid: 0) == nil && TimeMachinePermission.removeAppleScript(uid: 0) == nil, "as root (user ID 0) no rule is built and none is removed")
    let rootOutcome = await TimeMachinePermission.allow(uid: 0), rootRevoke = await TimeMachinePermission.revoke(uid: 0)
    expect(rootOutcome == .failed(TimeMachinePermission.rootRefusal) && rootRevoke == .failed(TimeMachinePermission.rootRefusal)
           && TimeMachinePermission.rootRefusal.contains("running as the administrator"), "allow and revoke as root say why nothing happens, and show no prompt")
    // one file per account
    expect(ruleFile == "/etc/sudoers.d/tmutil-thin-501" && TimeMachinePermission.ruleFile(uid: 502) != ruleFile && !URL(fileURLWithPath: ruleFile).lastPathComponent.contains("."),
           "each account has its own file, named by user ID with no dot (sudo skips names with a dot): \(ruleFile)")
    expect(TimeMachinePermission.legacyRuleFile == "/etc/sudoers.d/tmutil-thin" && !rootCommand.contains("\(TimeMachinePermission.legacyRuleFile) ") && !rootCommand.hasSuffix(TimeMachinePermission.legacyRuleFile),
           "the app's commands never touch the old shared file")
    var unquoted = rootCommand
    while let open = unquoted.firstIndex(of: "'"), let close = unquoted[unquoted.index(after: open)...].firstIndex(of: "'") { unquoted.removeSubrange(open...close) }
    expect(!unquoted.contains("#") && !unquoted.replacingOccurrences(of: "tmutil-thin-\(uid)", with: "").contains("\(uid)"), "the rule line carries the user ID only inside single quotes; outside them it is only in the file name")
    expect(TimeMachinePermission.ruleLine(uid: uid) == "#501 ALL=(root) NOPASSWD: /usr/bin/tmutil thinlocalsnapshots / 999999999999 4", "the rule names the user by number: \(TimeMachinePermission.ruleLine(uid: uid))")
    expect(rootCommand.contains("/usr/bin/install -S -m 0440 -o root -g wheel"), "the rule file is installed with -S, in one step")
    // a failing final check removes the rule just installed
    expect(rootCommand.contains("&& { /usr/sbin/visudo -c || { /bin/rm -f \(ruleFile) ; exit 3 ; } ; }"), "when the final visudo -c fails the new rule is removed again, and the command exits 3")

    // ---- the prompts say what is true ----
    expect(installScript.contains("with prompt \"Mac Analyzers wants to allow one command") && installScript.hasSuffix("with administrator privileges"), "the install dialog says what is allowed")
    expect(TimeMachinePermission.installPrompt.contains("any program running on this account can do that without asking"), "the install dialog says any program on the account can use it")
    expect(TimeMachinePermission.installPrompt.contains("remove the permission from the Time Machine screen") && !TimeMachinePermission.installPrompt.contains("Setup"),
           "the install dialog promises the removal where it is (the Time Machine screen), not Setup")
    expect(removeScript.contains("with prompt \"Mac Analyzers wants to remove the permission") && removeScript.contains("\"/bin/rm -f \(ruleFile)\""),
           "the removal is one fixed command behind its own prompt")
    expect(Names.TimeMachine.permissionDetail.contains("any program running on your account") && Names.TimeMachine.permissionDetail.contains("remove the permission from this screen"),
           "the bar beside Allow… says what the permission lets any program do, and where to remove it")

    // ---- the command the "earlier permission" bar shows ----
    let plain = TimeMachinePermission.uninstallCommand(suiteRoot: URL(fileURLWithPath: "/Users/someone/mac-analyzers"))
    expect(plain == "'/Users/someone/mac-analyzers/storage-analyzer/storage-manage-agents.sh' sudoers-uninstall", "the bar's command is the suite's own sudoers-uninstall, with the real path: \(plain)")
    let odd = TimeMachinePermission.uninstallCommand(suiteRoot: URL(fileURLWithPath: "/Applications/Mac Analyzers's.app/Contents/Resources/engine"))
    expect(odd.hasPrefix("'/Applications/Mac Analyzers'\\''s.app/") && odd.hasSuffix("storage-manage-agents.sh' sudoers-uninstall"), "a path with a space and a quote is quoted for a shell: \(odd)")
    expect(!plain.contains("sudo rm") && !Names.TimeMachine.earlierPermissionDetail.contains("sudo rm") && Names.TimeMachine.earlierPermissionDetail.contains("if it is this account's"),
           "the bar does not give a command that removes without checking, and says the removal happens only if the file is this account's")

    // ---- the template and the engine ----
    let template = (try? String(contentsOf: repo.appending(path: "storage-analyzer/sudoers.d/tmutil-thin"), encoding: .utf8)) ?? ""
    let active = template.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let templateTail = active.first.map { $0.split(separator: " ", maxSplits: 1).dropFirst().joined() } ?? ""
    let templateHead = active.first.map { String($0.split(separator: " ").first ?? "") } ?? ""
    expect(templateHead == "__UID__" && (active.first ?? "").replacingOccurrences(of: "__UID__", with: "#\(uid)") == TimeMachinePermission.ruleLine(uid: uid),
           "the template's first field is the __UID__ placeholder, and with the user ID put in it the template IS the app's line: \(active)")
    expect(!template.contains("__USERNAME__"), "the template has no account-name placeholder left")
    expect(active.count == 1 && templateTail == TimeMachinePermission.ruleTail, "the repository's template says, after its first field, the app's constant word for word: \(active)")
    expect(!(active.first ?? "").contains("*"), "the rule has no wildcard: the arguments must match exactly")
    for name in ["tm-reclaim.sh", "storage-auto-clean.sh"] {
        let text = (try? String(contentsOf: repo.appending(path: "storage-analyzer/\(name)"), encoding: .utf8)) ?? ""
        let uses = text.components(separatedBy: "\n").filter { $0.contains("/usr/bin/tmutil thinlocalsnapshots") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        expect(!uses.isEmpty && uses.allSatisfy { $0.contains(TimeMachinePermission.thinCommand) }, "\(name) runs exactly the allowed command line: \(uses)")
    }

    // ---- the environment the root shell starts with (H1) ----
    // What the shell inherits is what the Process built by the app says, or the app's own environment when it says
    // nothing. The probe's own environment is made hostile first, as `launchctl setenv` would make the app's.
    let hostile = root.appending(path: "hostile-env"), fakeBin = hostile.appending(path: "bin")
    for folder in ["bin", "etc", "rootdir", "standins", "cdpath"] { try? fm.createDirectory(at: hostile.appending(path: folder), withIntermediateDirectories: true) }
    let marker = hostile.appending(path: "MARKER")
    let touchMarker = "/usr/bin/touch \"\(marker.path)\""
    let hook = hostile.appending(path: "hook.sh")
    try? "\(touchMarker)\n".write(to: hook, atomically: true, encoding: .utf8)
    for fake in ["visudo", "install", "printf", "rm", "sed", "mktemp", "sudo", "touch2"] {
        let url = fakeBin.appending(path: fake)
        try? "#!/bin/bash\n\(touchMarker)\n".write(to: url, atomically: true, encoding: .utf8); chmod(url.path, 0o755)
    }
    let hostileEnvironment: [String: String] = [
        "BASH_FUNC_umask%%": "() { \(touchMarker); builtin umask \"$@\"; }",   // replaces the command's first word
        "SHELLOPTS": "xtrace", "PS4": "$(\(touchMarker)) ",                     // runs before any command
        "BASH_ENV": hook.path, "ENV": hook.path,
        "IFS": "/", "CDPATH": hostile.appending(path: "cdpath").path,
        "PATH": "\(fakeBin.path):/usr/bin:/bin",
    ]
    for (name, value) in hostileEnvironment { setenv(name, value, 1) }

    let etc = hostile.appending(path: "etc"), rootDir = hostile.appending(path: "rootdir"), standIns = hostile.appending(path: "standins")
    let log = root.appending(path: "root-stand-ins.log")
    func standIn(_ name: String, _ body: String) { let url = standIns.appending(path: name); try? body.write(to: url, atomically: true, encoding: .utf8); chmod(url.path, 0o755) }
    func workingStandIns() {
        standIn("visudo", "#!/bin/bash\necho \"visudo $*\" >> \"\(log.path)\"\nexit 0\n")
        standIn("install", "#!/bin/bash\necho \"install $*\" >> \"\(log.path)\"\nlast=\"${@: -1}\"; prev=\"${@: -2:1}\"; cp \"$prev\" \"$last\"\n")
    }
    workingStandIns()
    func simulated(_ command: String) -> String {
        command.replacingOccurrences(of: "/usr/sbin/visudo", with: standIns.appending(path: "visudo").path)
            .replacingOccurrences(of: "/usr/bin/install", with: standIns.appending(path: "install").path)
            .replacingOccurrences(of: "/private/var/root/", with: rootDir.path + "/")
            .replacingOccurrences(of: "/etc/sudoers.d/", with: etc.path + "/")
    }
    /// Runs the root command the way `do shell script` does (`/bin/sh -c`), with the system paths pointed at temp
    /// folders and the given environment. Never touches a real system path.
    func runSimulated(_ command: String, environment: [String: String]) -> Int32 {
        let simulation = simulated(command)
        let real = pathsIn(simulation).filter { $0.hasPrefix("/etc/") || $0.hasPrefix("/private/var/root") || $0.hasSuffix("/visudo") && !$0.hasPrefix(standIns.path) }
        guard real.isEmpty else { print("FAIL  the simulation would touch a real path: \(real)"); return 99 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", simulation]
        process.currentDirectoryURL = hostile
        process.environment = environment
        process.standardOutput = Pipe(); process.standardError = Pipe()
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
    func reset() { for url in [marker, etc.appending(path: "tmutil-thin-\(uid)"), rootDir.appending(path: ".mac-analyzers-tmutil-thin"), log] { try? fm.removeItem(at: url) } }

    // the app's own processes, built by the code that runs them
    let installProcess = TimeMachinePermission.osascript(installScript)
    let removeProcess = TimeMachinePermission.osascript(removeScript)
    for (what, process) in [("install", installProcess), ("remove", removeProcess)] {
        expect(process.environment == TimeMachinePermission.cleanEnvironment && process.environment?.keys.sorted() == ["LC_ALL", "PATH"],
               "the \(what) prompt's osascript is started with the app's own environment (PATH and LC_ALL), not the app's inherited one: \(String(describing: process.environment))")
    }
    // control: the same command under the hostile environment DOES run the attacker's code, so this check can see it
    reset()
    _ = runSimulated(rootCommand, environment: hostileEnvironment)
    expect(fm.fileExists(atPath: marker.path), "control: under a hostile environment the root shell runs the attacker's code (so the next case means something)")
    // the real case: the shell gets what the app's Process says; nothing of the hostile environment is in it
    reset()
    let shellEnvironment = installProcess.environment ?? ProcessInfo.processInfo.environment
    let status = runSimulated(rootCommand, environment: shellEnvironment)
    let installed = (try? String(contentsOf: etc.appending(path: "tmutil-thin-\(uid)"), encoding: .utf8)) ?? ""
    expect(status == 0 && installed == "\(TimeMachinePermission.ruleLine(uid: uid))\n", "with the app's environment the install writes the app's own line and nothing else: \(installed.debugDescription)")
    expect(!fm.fileExists(atPath: marker.path), "an exported umask function, SHELLOPTS with PS4, BASH_ENV, ENV, IFS, CDPATH and a PATH of fakes reach nothing, and none of the clone's fake programs run")
    let logged = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    expect(logged.contains("visudo -cf") && logged.contains("visudo -c\n") && logged.contains("install -S -m 0440 -o root -g wheel"), "visudo checked the file, installed it with -S, then checked the live configuration")
    expect(!fm.fileExists(atPath: rootDir.appending(path: ".mac-analyzers-tmutil-thin").path), "the scratch file is gone afterwards")
    expect(runSimulated(removeCommand, environment: removeProcess.environment ?? [:]) == 0 && !fm.fileExists(atPath: etc.appending(path: "tmutil-thin-\(uid)").path) && !fm.fileExists(atPath: marker.path),
           "the removal removes the rule and nothing else")
    // a failing check stops the install and leaves nothing behind
    reset(); standIn("visudo", "#!/bin/bash\nexit 1\n")
    let refused = runSimulated(rootCommand, environment: shellEnvironment)
    expect(refused != 0 && !fm.fileExists(atPath: etc.appending(path: "tmutil-thin-\(uid)").path) && !fm.fileExists(atPath: rootDir.appending(path: ".mac-analyzers-tmutil-thin").path),
           "when visudo refuses the file nothing is installed and the scratch file is removed (status \(refused))")
    // the live check failing AFTER the install removes the new rule again
    reset(); workingStandIns()
    standIn("visudo", "#!/bin/bash\n[[ \"$1\" == -c ]] && exit 1\nexit 0\n")
    let rolledBack = runSimulated(rootCommand, environment: shellEnvironment)
    expect(rolledBack == TimeMachinePermission.sudoersBrokenStatus && !fm.fileExists(atPath: etc.appending(path: "tmutil-thin-\(uid)").path) && !fm.fileExists(atPath: rootDir.appending(path: ".mac-analyzers-tmutil-thin").path),
           "when the live sudoers check fails after the install, the rule just installed is removed again and the command exits \(TimeMachinePermission.sudoersBrokenStatus) (status \(rolledBack))")
    // and the screen says what that means
    let said = TimeMachinePermission.installFailureText("0:60: execution error: /etc/sudoers.d/x: syntax error near line 3 (3)")
    expect(said.contains("error in another file") && said.contains("nothing of ours was left in place") && said.contains("syntax error near line 3") && !said.contains("(3)"),
           "a status 3 is explained as an error in another file, with nothing of ours left, and sudo's own words: \(said)")
    expect(TimeMachinePermission.installFailureText("execution error: User canceled. (-128)") == "execution error: User canceled. (-128)", "another failure is passed on as it is")
    for name in hostileEnvironment.keys { unsetenv(name) }

    // ---- every other program of this path: the environment each gets ----
    let envFile = root.appending(path: "ask-env.txt"), askLog = root.appending(path: "ask.log"), listing = root.appending(path: "listing.txt")
    func stub(_ name: String, rc: Int32, body: String = "") -> String {
        let url = root.appending(path: name)
        try? "#!/bin/bash\necho \"$*\" >> \"\(askLog.path)\"\n/usr/bin/env > \"\(envFile.path)\"\n/bin/cat \"\(listing.path)\"\nexit \(rc)\n".write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
        return url.path
    }
    let thin = TimeMachinePermission.thinCommand
    let administrator = "Matching Defaults entries for helderrodrigues on HR-Mac-Studio:\n    env_reset, !log_allowed\n\nUser helderrodrigues may run the following commands on HR-Mac-Studio:\n"
    // sudo's own listing for this Mac's account, with and without our rule (the first is a real listing)
    let withRule = administrator + "    (ALL) ALL\n    (root) NOPASSWD: \(thin)\n"
    let cases: [(String, String, Bool)] = [
        ("an administrator with our rule after (ALL) ALL", withRule, true),
        ("an administrator without our rule: (ALL) ALL needs a password", administrator + "    (ALL) ALL\n", false),
        ("another NOPASSWD entry that is not ours", administrator + "    (ALL) ALL\n    (root) NOPASSWD: /usr/bin/other\n", false),
        ("our rule, then (ALL) ALL after it: the last match wins and asks for a password", administrator + "    (root) NOPASSWD: \(thin)\n    (ALL) ALL\n", false),
        ("the command listed with a password", administrator + "    (root) PASSWD: \(thin)\n", false),
        ("a passwordless entry for another command, then ours with a password", administrator + "    (root) NOPASSWD: /bin/ls, PASSWD: \(thin)\n", false),
        ("our command passwordless in a list of commands", administrator + "    (root) NOPASSWD: /usr/bin/foo, \(thin), /usr/bin/bar\n", true),
        ("passwordless ALL for root: it works without our rule too", administrator + "    (ALL : ALL) NOPASSWD: ALL\n", true),
        ("our command passwordless but as another user", administrator + "    (operator) NOPASSWD: \(thin)\n", false),
        ("a denied item that carries the sticky NOPASSWD of ALL before it", administrator + "    (ALL) NOPASSWD: ALL, !\(thin)\n", false),
        ("our command denied after", administrator + "    (root) NOPASSWD: \(thin)\n    (root) !\(thin)\n", false),
        ("nothing listed", "Sorry, user x may not run sudo on host.\n", false),
        ("empty", "", false),
    ]
    for (what, text, expected) in cases {
        expect(TimeMachinePermission.listsPasswordless(text) == expected, "listing: \(what) reads as \(expected ? "allowed" : "not allowed yet")")
    }
    try? withRule.write(to: listing, atomically: true, encoding: .utf8)
    setenv("SHELLOPTS", "xtrace", 1); setenv("DYLD_INSERT_LIBRARIES", "/nonexistent.dylib", 1); setenv("BASH_ENV", hook.path, 1)
    var answer = await TimeMachinePermission.isAllowed(sudo: stub("sudo-ok", rc: 0))
    expect(answer, "sudo answering 0 with our rule listed reads as allowed")
    let seen = (try? String(contentsOf: envFile, encoding: .utf8)) ?? ""
    expect(seen.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin") && !seen.contains("SHELLOPTS") && !seen.contains("DYLD_") && !seen.contains("BASH_ENV"),
           "sudo is started with the clean environment, none of the app's: \(seen.replacingOccurrences(of: "\n", with: " "))")
    unsetenv("SHELLOPTS"); unsetenv("DYLD_INSERT_LIBRARIES"); unsetenv("BASH_ENV")
    // sudo answers 0 for an administrator who has no rule of ours, or only another passwordless entry: still not allowed
    for (what, text) in [("an administrator with no rule of ours", administrator + "    (ALL) ALL\n"), ("another passwordless entry", administrator + "    (ALL) ALL\n    (root) NOPASSWD: /usr/bin/other\n")] {
        try? text.write(to: listing, atomically: true, encoding: .utf8)
        answer = await TimeMachinePermission.isAllowed(sudo: stub("sudo-admin", rc: 0))
        expect(!answer, "sudo answering 0 for \(what) is not allowed yet (exit code alone is not the answer)")
    }
    try? withRule.write(to: listing, atomically: true, encoding: .utf8)
    for rc in [Int32(1), 2, 127] {
        answer = await TimeMachinePermission.isAllowed(sudo: stub("sudo-fail", rc: rc))
        expect(!answer, "sudo answering \(rc), even with our rule printed, is not allowed yet")
    }
    answer = await TimeMachinePermission.isAllowed(sudo: root.appending(path: "no-such-sudo").path)
    expect(!answer, "a sudo that cannot start is not allowed yet")
    expect(((try? String(contentsOf: askLog, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }.allSatisfy { $0 == "-n -l" }, "it only asks sudo to LIST, with no password prompt")

    // ---- is the backup disk there (M3): read-only `tmutil destinationinfo` ----
    let connected = "====================================================\nName          : Backups\nKind          : Local\nMount Point   : /Volumes/Backups\nID            : 8052ECF4\n"
    let away = "====================================================\nName          : Backups\nKind          : Local\nID            : 8052ECF4\n"
    for (what, text, expected) in [("a mounted disk", connected, TimeMachineDestination.Reach.connected), ("a disk that is not mounted", away, .notConnected),
                                   ("no destination", "tmutil: No destinations configured.\n", .notSetUp), ("something else", "garbage\n", .unknown), ("nothing", "", .unknown)] {
        expect(TimeMachineDestination.reach(from: text) == expected, "destinationinfo: \(what) reads as \(expected)")
    }
    try? connected.write(to: listing, atomically: true, encoding: .utf8)
    setenv("SHELLOPTS", "xtrace", 1)
    var reach = await TimeMachineDestination.current(tmutil: stub("tmutil-ok", rc: 0))
    expect(reach == .connected && ((try? String(contentsOf: envFile, encoding: .utf8)) ?? "").contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin") && !((try? String(contentsOf: envFile, encoding: .utf8)) ?? "").contains("SHELLOPTS"),
           "the disk question gets the clean environment and reads a mounted disk")
    unsetenv("SHELLOPTS")
    reach = await TimeMachineDestination.current(tmutil: stub("tmutil-bad", rc: 1))
    expect(reach == .unknown, "a tmutil that fails without a reason is unknown, not a guess")
    reach = await TimeMachineDestination.current(tmutil: root.appending(path: "no-such-tmutil").path)
    expect(reach == .unknown, "a tmutil that cannot start is unknown")
    for disk in [TimeMachineDestination.Reach.connected, .notConnected, .notSetUp, .unknown] {
        let words = CleanWords.timeMachine(backup: true, disk: disk).message
        expect(words.contains("can't be brought back") && words.contains("Deletes the local snapshots") && !words.localizedCaseInsensitiveContains("thinned") && words.contains("aren't touched"),
               "the confirmation says snapshots are deleted for good, for \(disk)")
    }
    expect(CleanWords.timeMachine(backup: true, disk: .notConnected).message.contains("isn't connected right now, so these snapshots are the only copies"), "an absent backup disk is said in the dialog")
    expect(CleanWords.timeMachine(backup: true, disk: .connected).message.contains("backup starts afterwards") && !CleanWords.timeMachine(backup: false, disk: .connected).message.contains("backup starts afterwards"),
           "the backup sentence follows the setting")
}
