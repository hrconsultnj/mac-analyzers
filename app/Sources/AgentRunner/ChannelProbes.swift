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
    func facts(_ clone: SourceClone, installed: String) -> CloneFacts { clone.facts(installed: installed) }

    // ── a clone with history, on the development branch
    let repo = root.appending(path: "clone", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    git(repo, ["init", "-q", "-b", "development"])
    let first = commit(repo, "a.txt", "one\n")
    let clone = SourceClone(root: repo)

    print("— This Copy: the clone this build came from —")
    check("equal: built from the clone's head, clean", ChannelLogic.thisCopy(build: build(commit: first), clone: facts(clone, installed: first)),
          .upToDate, channel: .thisCopy)

    _ = commit(repo, "b.txt", "two\n")
    let third = commit(repo, "c.txt", "three\n")
    check("behind: the clone has 2 commits the install lacks", ChannelLogic.thisCopy(build: build(commit: first), clone: facts(clone, installed: first)),
          .behind(changes: 2, uncommitted: false), channel: .thisCopy)

    write(repo, "a.txt", "one, edited\n")
    write(repo, "new.txt", "untracked\n")
    check("behind and dirty: 2 commits and uncommitted changes", ChannelLogic.thisCopy(build: build(commit: first), clone: facts(clone, installed: first)),
          .behind(changes: 2, uncommitted: true), channel: .thisCopy)
    check("same commit, dirty now, installed built clean: uncommitted work not installed",
          ChannelLogic.thisCopy(build: build(commit: third), clone: facts(clone, installed: third)),
          .behind(changes: 0, uncommitted: true), channel: .thisCopy)

    // the stamp build.sh makes (scripts/tree-hash.sh) and the clone's own reading must be the same value
    let hashScript = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "scripts/tree-hash.sh")
    func stamp(_ dir: URL) -> String {
        let shell = Process()
        shell.executableURL = hashScript
        shell.arguments = [dir.path]
        let shellOut = Pipe(); shell.standardOutput = shellOut
        try? shell.run()
        let value = String(decoding: shellOut.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        shell.waitUntilExit()
        return value
    }
    func sameHash(_ label: String) {
        let stamped = stamp(repo), read = clone.fingerprint
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
          ChannelLogic.thisCopy(build: build(commit: third, tree: builtWithUntracked, dirty: true), clone: facts(clone, installed: third)),
          .behind(changes: 0, uncommitted: true), channel: .thisCopy)
    write(repo, "new.txt", "untracked\n")
    check("same commit, installed built with exactly these uncommitted changes: up to date",
          ChannelLogic.thisCopy(build: build(commit: third, tree: stamped, dirty: true), clone: facts(clone, installed: third)),
          .upToDate, channel: .thisCopy)
    check("installed built with other uncommitted changes than the clone has now",
          ChannelLogic.thisCopy(build: build(commit: third, tree: String(repeating: "a", count: 64), dirty: true), clone: facts(clone, installed: third)),
          .behind(changes: 0, uncommitted: true), channel: .thisCopy)

    git(repo, ["checkout", "-q", "--", "."]); try? FileManager.default.removeItem(at: repo.appending(path: "new.txt"))
    check("the install had uncommitted changes the clone no longer has",
          ChannelLogic.thisCopy(build: build(commit: third, tree: stamped, dirty: true), clone: facts(clone, installed: third)),
          .differs(Names.ChannelText.installHadChangesCloneLost), channel: .thisCopy)

    git(repo, ["reset", "-q", "--hard", first])
    check("ahead: the install is from commits the clone has since reset away",
          ChannelLogic.thisCopy(build: build(commit: third), clone: facts(clone, installed: third)),
          .differs(Names.ChannelText.cloneIsBehindInstall), channel: .thisCopy)
    check("unrelated: the install's commit is not in the clone at all",
          ChannelLogic.thisCopy(build: build(commit: String(repeating: "b", count: 40)), clone: facts(clone, installed: String(repeating: "b", count: 40))),
          .differs(Names.ChannelText.cloneLacksCommit), channel: .thisCopy)
    check("an older build that recorded no commit",
          ChannelLogic.thisCopy(build: build(commit: nil), clone: facts(clone, installed: first)),
          .behind(changes: nil, uncommitted: false), channel: .thisCopy)

    let plain = root.appending(path: "download", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    let notClone = SourceClone(root: plain).isWorkingTree
    if notClone { failed += 1 }
    print("\(notClone ? "FAIL" : "PASS") a folder that is not a git working tree is not a clone")
    check("not a clone (a download): This Copy is unavailable", ChannelLogic.thisCopy(build: build(commit: first), clone: nil),
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

    print("\n\(failed == 0 ? "all channel states are as expected" : "\(failed) state(s) wrong")")
    ProbeScratch.finish(failed == 0 ? 0 : 1)
}
