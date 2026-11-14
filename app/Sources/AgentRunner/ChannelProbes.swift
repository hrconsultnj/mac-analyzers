import AnalyzersKit
import Foundation

/// `agent-runner --probe-channels`: the update channels' logic against a throwaway git repository. Each state
/// a person can be in on Beta and This Copy is built for real (a clone that is behind, equal, ahead of what
/// was installed, dirty, reset, not a clone at all), read with the same plain git the app uses, and printed with
/// the sentence the Updates screen says. Exits 1 when a state is not the expected one. Nothing here touches the
/// network (the Beta compare is given as GitHub would answer it) or the person's own clone.
func probeChannels() -> Never {
    var failed = 0
    func check(_ label: String, _ state: ChannelState, _ expected: ChannelState, channel: UpdateChannel) {
        let ok = state == expected
        if !ok { failed += 1 }
        print("\(ok ? "PASS" : "FAIL") \(label)\n       → \(state)\n       says: \(state.sentence(for: channel))" + (ok ? "" : "\n       expected: \(expected)"))
    }
    let root = ProbeScratch.folder("ma-probe-channels")

    @discardableResult func git(_ dir: URL, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=probe", "-c", "user.email=probe@example.invalid", "-c", "commit.gpgsign=false",
                             "-C", dir.path] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try? process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func write(_ dir: URL, _ name: String, _ text: String) { try? text.write(to: dir.appending(path: name), atomically: true, encoding: .utf8) }
    func commit(_ dir: URL, _ name: String, _ text: String) -> String {
        write(dir, name, text)
        git(dir, ["add", "-A"]); git(dir, ["commit", "-q", "-m", "change \(name)"])
        return git(dir, ["rev-parse", "HEAD"])
    }
    func build(commit: String?, tree: String? = "clean", dirty: Bool = false) -> BuildInfo {
        BuildInfo(release: "2.69.2", commitsAfter: 1, localChanges: dirty, commit: commit, branch: "development", treeHash: tree)
    }
    func facts(_ clone: SourceClone, installed: String) -> CloneFacts? { clone.facts(installed: installed) }

    // ── a clone with history, on the development branch
    let repo = root.appending(path: "clone", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    git(repo, ["init", "-q", "-b", "development"])
    let first = commit(repo, "a.txt", "one\n")
    let clone = SourceClone(root: repo)

    print("— This Copy: the clone this build came from —")
    check("equal: built from the clone's head, clean", ChannelLogic.thisCopy(build: build(commit: first), isClone: true, clone: facts(clone, installed: first)),
          .upToDate, channel: .thisCopy)

    _ = commit(repo, "b.txt", "two\n")
    let third = commit(repo, "c.txt", "three\n")
    check("behind: the clone has 2 commits the install lacks", ChannelLogic.thisCopy(build: build(commit: first), isClone: true, clone: facts(clone, installed: first)),
          .behind(changes: 2, uncommitted: false), channel: .thisCopy)

    write(repo, "a.txt", "one, edited\n")
    write(repo, "new.txt", "untracked\n")
    check("behind and dirty: 2 commits and uncommitted changes", ChannelLogic.thisCopy(build: build(commit: first), isClone: true, clone: facts(clone, installed: first)),
          .behind(changes: 2, uncommitted: true), channel: .thisCopy)
    check("same commit, dirty now, installed built clean: uncommitted work not installed",
          ChannelLogic.thisCopy(build: build(commit: third), isClone: true, clone: facts(clone, installed: third)),
          .behind(changes: 0, uncommitted: true), channel: .thisCopy)

    // the stamp build.sh makes (scripts/tree-hash.sh) and the clone's own reading must be the same value
    let hashScript = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "scripts/tree-hash.sh")
    func stamp(_ dir: URL) -> String {
        let shell = Process()
        shell.executableURL = hashScript
        shell.arguments = [dir.path]
        let shellOut = Pipe(); shell.standardOutput = shellOut
        shell.standardInput = FileHandle.nullDevice
        try? shell.run()
        let value = String(decoding: shellOut.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        shell.waitUntilExit()
        return shell.terminationStatus == 0 ? value : ""        // a failed script is "unknown", whatever it printed
    }
    func sameHash(_ label: String) {
        let stamped = stamp(repo), read = clone.fingerprint ?? "nil"
        let ok = stamped == read && (stamped == "clean" || stamped.count == 64)
        if !ok { failed += 1 }
        print("\(ok ? "PASS" : "FAIL") \(label): build.sh's tree hash equals the app's reading\n       (\(stamped.prefix(12))… vs \(read.prefix(12))…)")
    }
    let stamped = stamp(repo)
    sameHash("tracked edit and an untracked file")

    // awkward untracked files: spaces, a line break in the name, bytes with NUL, an empty file, a UTF-8 name
    write(repo, "with space.txt", "a b\n")
    write(repo, "line\nbreak.txt", "two lines\n")
    write(repo, "naïve é.txt", "utf8\n")
    write(repo, "empty.txt", "")
    try? Data([0, 1, 2, 0, 255, 10, 0]).write(to: repo.appending(path: "binary.bin"))
    sameHash("untracked names with spaces, a line break, UTF-8, an empty file and bytes with NUL")

    // the person's git configuration must not change the bytes
    git(repo, ["config", "diff.external", "/usr/bin/false"]); git(repo, ["config", "diff.noprefix", "true"])
    git(repo, ["config", "color.ui", "always"]); git(repo, ["config", "diff.algorithm", "patience"])
    git(repo, ["config", "core.quotepath", "true"]); git(repo, ["config", "diff.renames", "copies"])
    sameHash("with an external diff tool, colour, no prefix, another algorithm and quoted paths configured")
    for key in ["diff.external", "diff.noprefix", "color.ui", "diff.algorithm", "core.quotepath", "diff.renames"] { git(repo, ["config", "--unset", key]) }
    for name in ["with space.txt", "line\nbreak.txt", "naïve é.txt", "empty.txt", "binary.bin"] { try? FileManager.default.removeItem(at: repo.appending(path: name)) }
    sameHash("after the awkward files are removed")

    // the case the bytes of untracked files exist for: a new file edited after the build
    let builtWithUntracked = stamp(repo)
    write(repo, "new.txt", "untracked, edited after the build\n")
    check("an untracked file changed after the build: not up to date",
          ChannelLogic.thisCopy(build: build(commit: third, tree: builtWithUntracked, dirty: true), isClone: true, clone: facts(clone, installed: third)),
          .behind(changes: 0, uncommitted: true), channel: .thisCopy)
    write(repo, "new.txt", "untracked\n")
    check("same commit, installed built with exactly these uncommitted changes: up to date",
          ChannelLogic.thisCopy(build: build(commit: third, tree: stamped, dirty: true), isClone: true, clone: facts(clone, installed: third)),
          .upToDate, channel: .thisCopy)
    check("installed built with other uncommitted changes than the clone has now",
          ChannelLogic.thisCopy(build: build(commit: third, tree: String(repeating: "a", count: 64), dirty: true), isClone: true, clone: facts(clone, installed: third)),
          .behind(changes: 0, uncommitted: true), channel: .thisCopy)

    git(repo, ["checkout", "-q", "--", "."]); try? FileManager.default.removeItem(at: repo.appending(path: "new.txt"))
    check("the install had uncommitted changes the clone no longer has",
          ChannelLogic.thisCopy(build: build(commit: third, tree: stamped, dirty: true), isClone: true, clone: facts(clone, installed: third)),
          .differs(Names.ChannelText.installHadChangesCloneLost), channel: .thisCopy)

    git(repo, ["reset", "-q", "--hard", first])
    check("ahead: the install is from commits the clone has since reset away",
          ChannelLogic.thisCopy(build: build(commit: third), isClone: true, clone: facts(clone, installed: third)),
          .differs(Names.ChannelText.cloneIsBehindInstall), channel: .thisCopy)
    check("unrelated: the install's commit is not in the clone at all",
          ChannelLogic.thisCopy(build: build(commit: String(repeating: "b", count: 40)), isClone: true, clone: facts(clone, installed: String(repeating: "b", count: 40))),
          .differs(Names.ChannelText.cloneLacksCommit), channel: .thisCopy)
    check("an older build that recorded no commit",
          ChannelLogic.thisCopy(build: build(commit: nil), isClone: true, clone: facts(clone, installed: first)),
          .behind(changes: nil, uncommitted: false), channel: .thisCopy)

    let plain = root.appending(path: "download", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    let notClone = SourceClone(root: plain).isWorkingTree
    if notClone { failed += 1 }
    print("\(notClone ? "FAIL" : "PASS") a folder that is not a git working tree is not a clone")
    check("not a clone (a download): This Copy is unavailable", ChannelLogic.thisCopy(build: build(commit: first), isClone: false, clone: nil),
          .unavailable(Names.ChannelText.notAClone), channel: .thisCopy)

    print("\n— Beta: the newest commit on development on GitHub —")
    check("equal: GitHub says identical", ChannelLogic.beta(build: build(commit: first), cloneBranch: "development", isClone: true,
                                                          compare: BetaCompare(status: "identical", aheadBy: 0)),
          .upToDate, channel: .beta)
    check("behind: development has 5 more commits", ChannelLogic.beta(build: build(commit: first), cloneBranch: "development", isClone: true,
                                                                    compare: BetaCompare(status: "ahead", aheadBy: 5, newest: "abc1234 · Fix the thing")),
          .behind(changes: 5, uncommitted: false), channel: .beta)
    check("ahead: this copy has commits development lacks", ChannelLogic.beta(build: build(commit: first), cloneBranch: "development", isClone: true,
                                                                            compare: BetaCompare(status: "behind", aheadBy: 0)),
          .ahead(Names.ChannelText.aheadOfDevelopment), channel: .beta)
    check("built from commits GitHub does not have", ChannelLogic.beta(build: build(commit: first), cloneBranch: "development", isClone: true,
                                                                      compare: BetaCompare(status: "missing", aheadBy: 0)),
          .ahead(Names.ChannelText.notOnGitHub), channel: .beta)
    check("diverged", ChannelLogic.beta(build: build(commit: first), cloneBranch: "development", isClone: true,
                                       compare: BetaCompare(status: "diverged", aheadBy: 2)),
          .ahead(Names.ChannelText.divergedFromDevelopment), channel: .beta)
    check("offline: nothing answered", ChannelLogic.beta(build: build(commit: first), cloneBranch: "development", isClone: true, compare: nil),
          .unknown(Names.ChannelText.offline), channel: .beta)
    check("a clone on another branch cannot follow development", ChannelLogic.beta(build: build(commit: first), cloneBranch: "main", isClone: true,
                                                                                 compare: BetaCompare(status: "ahead", aheadBy: 5)),
          .unavailable(Names.ChannelText.notOnDevelopment("main")), channel: .beta)
    check("a download cannot follow a branch", ChannelLogic.beta(build: build(commit: first), cloneBranch: nil, isClone: false, compare: nil),
          .unavailable(Names.ChannelText.notAClone), channel: .beta)
    check("an older build that recorded no commit is offered the newest once", ChannelLogic.beta(build: build(commit: nil), cloneBranch: "development", isClone: true, compare: nil),
          .behind(changes: nil, uncommitted: false), channel: .beta)

    // ── reading a clone must run nothing the clone names, and a failure is never "clean"
    print("\n— a hostile clone: nothing it names may run —")
    let hostile = root.appending(path: "hostile", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: hostile, withIntermediateDirectories: true)
    let markers = root.appending(path: "markers.txt")
    func script(_ name: String) -> String {
        let url = root.appending(path: "run-\(name).sh")
        try? "#!/bin/sh\necho \(name) >> '\(markers.path)'\ncat\n".write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
        return url.path
    }
    git(hostile, ["init", "-q", "-b", "development"])
    write(hostile, "a.txt", "one\n"); write(hostile, "b.bin", "bin\n"); write(hostile, "c.log", "log\n")
    git(hostile, ["add", "-A"]); git(hostile, ["commit", "-q", "-m", "first"])
    let hostileHead = git(hostile, ["rev-parse", "HEAD"])
    // everything that can name a program: in the clone's own configuration, its attributes, its info/attributes,
    // an included file, a hooks folder, and an attributes file
    write(hostile, ".gitattributes", "*.txt filter=evil diff=evildiff\n")
    write(root, "included.config", "[core]\n\tfsmonitor = \(script("include-fsmonitor"))\n")
    let hooks = root.appending(path: "hooks", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
    for hook in ["pre-commit", "post-checkout", "post-merge", "reference-transaction", "fsmonitor-watchman"] {
        try? "#!/bin/sh\necho hook-\(hook) >> '\(markers.path)'\n".write(to: hooks.appending(path: hook), atomically: true, encoding: .utf8)
        chmod(hooks.appending(path: hook).path, 0o755)
    }
    write(root, "global.attributes", "*.log filter=evil3\n")
    try? "*.bin filter=evil2\n".write(to: hostile.appending(path: ".git/info/attributes"), atomically: true, encoding: .utf8)
    let settings: [(String, String)] = [
        ("core.fsmonitor", script("fsmonitor")), ("include.path", root.appending(path: "included.config").path),
        ("filter.evil.clean", script("clean-filter")), ("filter.evil.smudge", script("smudge-filter")),
        ("filter.evil.process", script("process-filter")), ("filter.evil2.clean", script("info-attributes-filter")),
        ("filter.evil3.clean", script("attributes-file-filter")), ("core.attributesFile", root.appending(path: "global.attributes").path),
        ("diff.evildiff.textconv", script("textconv")), ("diff.evildiff.command", script("diff-driver")),
        ("diff.external", script("external-diff")), ("core.hooksPath", hooks.path), ("core.pager", script("pager")),
        ("pager.diff", script("pager-diff")), ("core.sshCommand", script("ssh")), ("credential.helper", script("credential")),
        ("gpg.program", script("gpg")), ("uploadpack.packObjectsHook", script("uploadpack")),
        ("core.editor", script("editor")), ("sequence.editor", script("sequence-editor")),
    ]
    for (key, value) in settings { git(hostile, ["config", key, value]) }
    git(hostile, ["config", "includeIf.gitdir:\(hostile.path)/.path", root.appending(path: "included.config").path])
    // work to find, so status and diff have a reason to run their filters
    write(hostile, "a.txt", "one, edited\n"); write(hostile, "b.bin", "bin, edited\n"); write(hostile, "c.log", "log, edited\n")
    write(hostile, "new.txt", "untracked\n")
    func fired() -> [String] {
        ((try? String(contentsOf: markers, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }
    // control: plain git on this clone DOES run them, so the setup is a real test
    try? FileManager.default.removeItem(at: markers)
    for command in [["status", "--porcelain"], ["diff", "HEAD"], ["ls-files", "--others"]] {
        let control = Process()
        control.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        control.arguments = ["-C", hostile.path] + command
        control.standardOutput = FileHandle.nullDevice; control.standardError = FileHandle.nullDevice
        control.standardInput = FileHandle.nullDevice
        try? control.run(); control.waitUntilExit()
    }
    let control = Set(fired())
    let controlOK = !control.isEmpty
    if !controlOK { failed += 1 }
    print("\(controlOK ? "PASS" : "FAIL") control: plain git on this clone runs \(control.sorted()) (the test can fail)")
    try? FileManager.default.removeItem(at: markers)
    /// The root the way the app builds it (`AnalyzersPaths.suiteRoot`: `appending(path:)`, no trailing slash). The probes'
    /// other roots are folder URLs with a trailing slash, and a path resolved against one of those works where it
    /// silently looks in the wrong place against the app's.
    func asApp(_ dir: URL) -> URL { dir.deletingLastPathComponent().appending(path: dir.lastPathComponent) }
    let appFormRoot = asApp(hostile)
    let rootFormOK = !appFormRoot.absoluteString.hasSuffix("/") && appFormRoot.path == hostile.path
    if !rootFormOK { failed += 1 }
    print("\(rootFormOK ? "PASS" : "FAIL") the hostile clone is read through a root built the way the app builds its own (no trailing slash): \(appFormRoot.absoluteString.suffix(24))")
    let hostileClone = SourceClone(root: appFormRoot)
    _ = hostileClone.isWorkingTree; _ = hostileClone.branch; _ = hostileClone.head; _ = hostileClone.isDirty
    _ = hostileClone.fingerprint; _ = hostileClone.facts(installed: hostileHead); _ = hostileClone.changelog
    _ = stamp(hostile)
    let ran = fired()
    if !ran.isEmpty { failed += 1 }
    print("\(ran.isEmpty ? "PASS" : "FAIL") reading the hostile clone (every read the app makes, and scripts/tree-hash.sh) ran nothing: \(ran.isEmpty ? "no marker" : Set(ran).sorted().joined(separator: ", "))")
    // its .git/info/attributes names a filter: that is the one place left that can pick a driver, so it reads unknown
    let infoUnknown = hostileClone.fingerprint == nil && hostileClone.facts(installed: hostileHead) == nil && stamp(hostile).isEmpty
    if !infoUnknown { failed += 1 }
    print("\(infoUnknown ? "PASS" : "FAIL") a non-empty .git/info/attributes reads unknown (app and script), never clean")
    // with it gone the clone still has filters, drivers and .gitattributes configured, and is read normally
    try? FileManager.default.removeItem(at: hostile.appending(path: ".git/info/attributes"))
    try? FileManager.default.removeItem(at: markers)
    print("\(stamp(hostile).count == 64 ? "PASS" : "FAIL") …and without it the hash of its uncommitted work is a real hash")
    if stamp(hostile).count != 64 { failed += 1 }
    let sameAsApp = stamp(hostile) == hostileClone.fingerprint
    if !sameAsApp { failed += 1 }
    let stillSilent = fired().isEmpty
    if !stillSilent { failed += 1 }
    print("\(stillSilent ? "PASS" : "FAIL") …and reading it that way still runs nothing")
    print("\(sameAsApp ? "PASS" : "FAIL") the script and the app still agree on a clone with .gitattributes and filters configured")

    // ── more hostile shapes, each proved to run something under plain git and nothing through the app and the script
    print("\n— more hostile clones —")
    /// A program the clone names: it writes its name to the marker, and (a filter) passes its input through,
    /// unless it is a protocol program that must not wait for input (fsmonitor, uploadpack).
    func marked(_ marker: URL, _ name: String, passThrough: Bool = true) -> String {
        let url = root.appending(path: "run2-\(name).sh")
        try? "#!/bin/sh\necho \(name) >> '\(marker.path)'\n\(passThrough ? "cat\n" : "exit 1\n")".write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
        return url.path
    }
    func plainGitFires(_ dir: URL, _ marker: URL) -> Set<String> {
        try? FileManager.default.removeItem(at: marker)
        for command in [["status", "--porcelain"], ["diff", "HEAD"]] {
            let control = Process()
            control.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            control.arguments = ["-C", dir.path] + command
            control.standardOutput = FileHandle.nullDevice; control.standardError = FileHandle.nullDevice
            control.standardInput = FileHandle.nullDevice
            try? control.run(); control.waitUntilExit()
        }
        let fired = Set(((try? String(contentsOf: marker, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
        try? FileManager.default.removeItem(at: marker)
        return fired
    }
    func hostileCase(_ label: String, _ dir: URL, _ marker: URL, unknown: Bool) {
        let controlFired = plainGitFires(dir, marker)
        let controlOK = !controlFired.isEmpty
        if !controlOK { failed += 1 }
        print("\(controlOK ? "PASS" : "FAIL") \(label): plain git runs \(controlFired.sorted()) (the test can fail)")
        let clone = SourceClone(root: asApp(dir))
        _ = clone.isWorkingTree; _ = clone.branch; _ = clone.head; _ = clone.isDirty
        let fingerprint = clone.fingerprint
        let facts = clone.facts(installed: clone.head)
        let stamped = stamp(dir)
        let fired = ((try? String(contentsOf: marker, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        let silent = fired.isEmpty
        if !silent { failed += 1 }
        print("\(silent ? "PASS" : "FAIL")    through the app and tree-hash.sh: \(silent ? "nothing ran" : "RAN " + Set(fired).sorted().joined(separator: ", "))")
        if unknown {
            let ok = fingerprint == nil && facts == nil && stamped.isEmpty
            if !ok { failed += 1 }
            print("\(ok ? "PASS" : "FAIL")    and it reads unknown (fingerprint, facts and the script's hash are all nil/empty), never clean"
                  + (ok ? "" : " — fingerprint \(fingerprint ?? "nil"), facts \(facts == nil ? "nil" : "read"), script \(stamped.isEmpty ? "empty" : stamped)"))
        }
    }
    func fresh(_ name: String) -> (URL, URL) {
        let dir = root.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        git(dir, ["init", "-q", "-b", "development"])
        return (dir, root.appending(path: "markers-\(name).txt"))
    }
    // t5: a driver whose name contains "=" (cannot be named by -c), picked by info/attributes
    do {
        let (dir, marker) = fresh("t5-equals")
        _ = commit(dir, "x.txt", "one\n")
        if let handle = try? FileHandle(forWritingTo: dir.appending(path: ".git/config")) {
            handle.seekToEndOfFile()
            handle.write(Data("[filter \"a=b\"]\n\tclean = \(marked(marker, "equals-filter"))\n".utf8))
            try? handle.close()
        }
        try? "*.txt filter=a=b\n".write(to: dir.appending(path: ".git/info/attributes"), atomically: true, encoding: .utf8)
        write(dir, "x.txt", "edited\n")
        hostileCase("a filter whose name contains '='", dir, marker, unknown: true)
    }
    // t7: a submodule whose own configuration and info/attributes pick a filter
    do {
        let (source, _) = fresh("t7-src")
        _ = commit(source, "s.txt", "inside\n")
        let (dir, marker) = fresh("t7-submodule")
        _ = commit(dir, "p.txt", "parent\n")
        git(dir, ["-c", "protocol.file.allow=always", "submodule", "add", "-q", source.path, "sub"])
        git(dir, ["add", "-A"]); git(dir, ["commit", "-q", "-m", "add the submodule"])
        let inner = dir.appending(path: ".git/modules/sub")
        if let handle = try? FileHandle(forWritingTo: inner.appending(path: "config")) {
            handle.seekToEndOfFile()
            handle.write(Data("[filter \"evil\"]\n\tclean = \(marked(marker, "submodule-filter"))\n[core]\n\tfsmonitor = \(marked(marker, "submodule-fsmonitor", passThrough: false))\n".utf8))
            try? handle.close()
        }
        try? FileManager.default.createDirectory(at: inner.appending(path: "info"), withIntermediateDirectories: true)
        try? "*.txt filter=evil\n".write(to: inner.appending(path: "info/attributes"), atomically: true, encoding: .utf8)
        write(dir.appending(path: "sub", directoryHint: .isDirectory), "s.txt", "inside, edited\n")
        write(dir, "p.txt", "parent, edited\n")
        hostileCase("a submodule that names a filter, a program and its own attributes", dir, marker, unknown: true)
    }
    // t10: a partial clone whose promisor remote's uploadpack is a script (git would run it to fetch a missing blob)
    do {
        let (source, _) = fresh("t10-src")
        git(source, ["config", "uploadpack.allowFilter", "true"]); git(source, ["config", "uploadpack.allowAnySHA1InWant", "true"])
        _ = commit(source, "big.txt", "lots of text\n")
        let dir = root.appending(path: "t10-partial", directoryHint: .isDirectory)
        git(root, ["clone", "-q", "--filter=blob:none", "--no-checkout", "file://\(source.path)", dir.path])
        git(dir, ["read-tree", "HEAD"])
        let marker = root.appending(path: "markers-t10.txt")
        git(dir, ["config", "remote.origin.uploadpack", marked(marker, "uploadpack", passThrough: false)])
        write(dir, "big.txt", "different text\n")
        hostileCase("a partial clone whose promisor remote names a program", dir, marker, unknown: true)
    }

    // a submodule edit with the superproject clean: git is never run inside a submodule, so "clean" would be a guess
    do {
        let (source, _) = fresh("t12-src")
        _ = commit(source, "s.txt", "inside\n")
        let (dir, _) = fresh("t12-clean-super")
        _ = commit(dir, "p.txt", "parent\n")
        git(dir, ["-c", "protocol.file.allow=always", "submodule", "add", "-q", source.path, "sub"])
        git(dir, ["add", "-A"]); git(dir, ["commit", "-q", "-m", "add the submodule"])
        write(dir.appending(path: "sub", directoryHint: .isDirectory), "s.txt", "inside, edited and not committed\n")
        let plain = git(dir, ["status", "--porcelain", "--ignore-submodules=none"])
        let seesIt = plain.contains("sub")
        if !seesIt { failed += 1 }
        print("\(seesIt ? "PASS" : "FAIL") control: plain git sees the edit inside the submodule: \(plain)")
        let clone = SourceClone(root: asApp(dir))
        let unknown = clone.isDirty == nil && clone.fingerprint == nil && clone.facts(installed: clone.head) == nil && stamp(dir).isEmpty
        if !unknown { failed += 1 }
        print("\(unknown ? "PASS" : "FAIL") …and with the superproject clean the app and the script read unknown, never \"matches your clone\"")
    }

    // the info/attributes check looks in the CLONE's folder, however the root is written
    do {
        let (dir, _) = fresh("t1-attributes-form")
        _ = commit(dir, "a.txt", "one\n")
        try? "*.xyz text\n".write(to: dir.appending(path: ".git/info/attributes"), atomically: true, encoding: .utf8)
        write(dir, "a.txt", "two\n")
        let folderForm = SourceClone(root: dir).facts(installed: nil) == nil
        let appForm = SourceClone(root: asApp(dir)).facts(installed: nil) == nil
        if !(folderForm && appForm) { failed += 1 }
        print("\(folderForm && appForm ? "PASS" : "FAIL") a non-empty info/attributes reads unknown with a folder root and with the app's root (no trailing slash)")
    }

    // which tag a build counts from: only a tag that is a version counts
    print("\n— which release tag a build counts from —")
    do {
        let tagScript = hashScript.deletingLastPathComponent().deletingLastPathComponent().appending(path: "app/release-tag.sh")
        func counted(_ dir: URL, version: String) -> String {
            let process = Process()
            process.executableURL = tagScript
            process.arguments = [dir.path, version]
            let out = Pipe(); process.standardOutput = out; process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try? process.run()
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            process.waitUntilExit()
            return text
        }
        func expectTag(_ label: String, _ got: String, _ expected: String) {
            let ok = got == expected
            if !ok { failed += 1 }
            print("\(ok ? "PASS" : "FAIL") \(label): \"\(got)\"\(ok ? "" : "   (expected \"\(expected)\")")")
        }
        let (dir, _) = fresh("tags")
        _ = commit(dir, "a.txt", "one\n")
        git(dir, ["tag", "v2.69.2"])
        _ = commit(dir, "b.txt", "two\n")
        expectTag("VERSION 2.69.2 and its tag exists: counted from it", counted(dir, version: "2.69.2"), "v2.69.2 1")
        expectTag("VERSION 2.70.0 ahead of every tag: the nearest version tag", counted(dir, version: "2.70.0"), "v2.69.2 1")
        git(dir, ["tag", "v9-junk"])
        expectTag("a junk tag at HEAD (v9-junk) is not a version: still the real tag", counted(dir, version: "2.70.0"), "v2.69.2 1")
        let (only, _) = fresh("tags-junk-only")
        _ = commit(only, "a.txt", "one\n")
        git(only, ["tag", "v9-junk"]); git(only, ["tag", "v2.70.0-rc1"])
        expectTag("only junk and a release candidate tag in reach: no tag is counted", counted(only, version: "2.70.0"), "")
        git(dir, ["tag", "v2.70.0"])
        expectTag("the tag of VERSION appears: counted from it", counted(dir, version: "2.70.0"), "v2.70.0 0")
    }

    print("\n— hashing a large file keeps memory flat —")
    do {
        let (dir, _) = fresh("big")
        _ = commit(dir, "a.txt", "one\n")
        write(dir, "a.txt", "two\n")
        let size: UInt64 = 400 * 1_048_576
        FileManager.default.createFile(atPath: dir.appending(path: "recording.bin").path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: dir.appending(path: "recording.bin")) { try? handle.truncate(atOffset: size); try? handle.close() }
        func peak() -> Int { var usage = rusage(); getrusage(RUSAGE_SELF, &usage); return Int(usage.ru_maxrss) }
        let before = peak()
        let started = Date()
        let hashed = SourceClone(root: dir).fingerprint
        let grown = (peak() - before) / 1_048_576
        let ok = hashed?.count == 64 && grown < 100
        if !ok { failed += 1 }
        print("\(ok ? "PASS" : "FAIL") a 400 MB untracked file: hashed in \(String(format: "%.1f", Date().timeIntervalSince(started))) s, peak memory grew by \(grown) MB (limit 100)")
    }

    print("\n— what a This Copy read costs —")
    let own = hashScript.deletingLastPathComponent().deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: own.appending(path: ".git").path) {
        let started = Date()
        let read = SourceClone(root: own).facts(installed: SourceClone(root: own).head)
        print("info: one read of this repository (\(read == nil ? "unknown" : "read")) took \(String(format: "%.2f", Date().timeIntervalSince(started))) s, run off the main thread by UpdateState")
    }

    print("\n— a failure is never \"clean\" —")
    let broken = root.appending(path: "broken", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    git(broken, ["init", "-q", "-b", "development"])
    let brokenFirst = commit(broken, "a.txt", "one\n")
    write(broken, "a.txt", "edited\n")
    let index = broken.appending(path: ".git/index").path
    chmod(index, 0o000)
    let brokenClone = SourceClone(root: broken)
    let brokenFacts = brokenClone.facts(installed: brokenFirst)
    let unreadable = brokenClone.isDirty == nil && brokenClone.fingerprint == nil && brokenFacts == nil
    if !unreadable { failed += 1 }
    print("\(unreadable ? "PASS" : "FAIL") an unreadable index with a tracked edit: dirty, fingerprint and facts are nil (unknown), not clean")
    check("   and This Copy says unknown, not that it matches", ChannelLogic.thisCopy(build: build(commit: brokenFirst), isClone: true, clone: brokenFacts),
          .unknown(Names.ChannelText.cannotRead), channel: .thisCopy)
    let scriptFails = Process()
    scriptFails.executableURL = hashScript; scriptFails.arguments = [broken.path]
    let scriptOut = Pipe(); scriptFails.standardOutput = scriptOut; scriptFails.standardError = FileHandle.nullDevice
    scriptFails.standardInput = FileHandle.nullDevice
    try? scriptFails.run(); scriptFails.waitUntilExit()
    let scriptPrinted = String(decoding: scriptOut.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let scriptFailed = scriptFails.terminationStatus != 0 && !scriptPrinted.contains("clean")
    if !scriptFailed { failed += 1 }
    print("\(scriptFailed ? "PASS" : "FAIL") scripts/tree-hash.sh exits non-zero and prints nothing for it (a build then stamps \"unknown\", never \"clean\")")
    chmod(index, 0o644)

    print("\n— settings that hide work cannot hide it —")
    let hidden = root.appending(path: "hidden", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    git(hidden, ["init", "-q", "-b", "development"])
    _ = commit(hidden, "a.txt", "one\n")
    git(hidden, ["config", "status.showUntrackedFiles", "no"])
    git(hidden, ["config", "diff.ignoreSubmodules", "all"])
    write(hidden, "NewFile.swift", "let x = 1\n")
    let hiddenClone = SourceClone(root: hidden)
    let seen = hiddenClone.isDirty == true && stamp(hidden).count == 64
    if !seen { failed += 1 }
    print("\(seen ? "PASS" : "FAIL") status.showUntrackedFiles=no in the clone: the new file still makes it dirty and is hashed")
    let before = stamp(hidden)
    write(hidden, "NewFile.swift", "let x = 2\n")
    let edited = stamp(hidden) != before && hiddenClone.fingerprint == stamp(hidden)
    if !edited { failed += 1 }
    print("\(edited ? "PASS" : "FAIL") …and an edit to it changes the hash, in the script and in the app")

    print("\n— a folder inside a bigger repository is not a clone —")
    let inner = repo.appending(path: "inside", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    let innerIsClone = SourceClone(root: inner).isWorkingTree
    if innerIsClone { failed += 1 }
    print("\(innerIsClone ? "FAIL" : "PASS") a folder inside a repository (a home folder that is a dotfiles repo) is not taken for the clone")

    print("\n\(failed == 0 ? "all channel states are as expected" : "\(failed) state(s) wrong")")
    ProbeScratch.finish(failed == 0 ? 0 : 1)
}
