@_spi(TestSupport) import AnalyzersKit
import Foundation

/// `agent-runner --probe-versions`: what version a build IS, and how versions compare. A build exactly at its
/// release tag with a clean tree is that release; any other build is the next patch, `-dev.<commits since the
/// tag>`, `+<short commit>` and `.local` for uncommitted changes (semantic versioning), so it never shows
/// the release's own number and is never offered a release it is already past. Also runs the owner's flow on a
/// throwaway clone: This Copy, Check Now, what is newer in the clone, and the Rebuild button.
@MainActor
func probeVersions() async -> Never {
    var failed = 0
    func expect(_ label: String, _ got: String, _ expected: String) {
        let ok = got == expected
        if !ok { failed += 1 }
        print("\(ok ? "PASS" : "FAIL") \(label): \(got)\(ok ? "" : "   (expected \(expected))")")
    }
    func flag(_ label: String, _ got: Bool, _ expected: Bool) {
        let ok = got == expected
        if !ok { failed += 1 }
        print("\(ok ? "PASS" : "FAIL") \(label): \(got)")
    }
    let commit = "8e2c9b0aa11122233344455566677788899900"

    print("— the version of a build —")
    expect("at the tag, clean tree", BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit).version, "2.69.2")
    expect("at the tag, uncommitted changes", BuildInfo(release: "2.69.2", commitsAfter: 0, localChanges: true, commit: commit).version, "2.69.3-dev.0+8e2c9b0.local")
    expect("42 commits after the tag", BuildInfo(release: "2.69.2", commitsAfter: 42, commit: commit).version, "2.69.3-dev.42+8e2c9b0")
    expect("42 commits after the tag, uncommitted changes", BuildInfo(release: "2.69.2", commitsAfter: 42, localChanges: true, commit: commit).version, "2.69.3-dev.42+8e2c9b0.local")
    expect("no release tag in reach (a clone, no count)", BuildInfo(release: "2.69.2", commitsAfter: nil, commit: commit).version, "2.69.3-dev+8e2c9b0")
    expect("no release tag in reach, uncommitted changes", BuildInfo(release: "2.69.2", commitsAfter: nil, localChanges: true, commit: commit).version, "2.69.3-dev+8e2c9b0.local")
    expect("not a clone (a download: no stamp)", BuildInfo(release: "2.69.2", commitsAfter: nil).version, "2.69.2")
    expect("short form for the sidebar", BuildInfo(release: "2.69.2", commitsAfter: 42, localChanges: true, commit: commit).shortVersion, "2.69.3-dev.42")
    expect("sidebar line", BuildInfo(release: "2.69.2", commitsAfter: 42, commit: commit).sidebarText, "Version 2.69.3-dev.42")
    expect("a release's sidebar line is unchanged", BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit).sidebarText, "Version 2.69.2")
    expect("the Updates screen names it in full", BuildInfo(release: "2.69.2", commitsAfter: 42, localChanges: true, commit: commit).versionText, "v2.69.3-dev.42+8e2c9b0.local · Dev Build")
    expect("the footer is short", BuildInfo(release: "2.69.2", commitsAfter: 42, commit: commit).shortVersionText, "v2.69.3-dev.42 · Dev Build")
    expect("git could not say whether the tree was clean: the version says so, never silently clean",
           BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit, treeHash: "unknown").version, "2.69.3-dev.0+8e2c9b0.unknown")
    expect("   (and it is not a release)", String(BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit, treeHash: "unknown").isDevelopment), "true")
    expect("the next patch after a minor", BuildInfo.nextPatch(after: "2.70.0"), "2.70.1")

    print("\n— semantic-versioning precedence —")
    flag("2.69.3-dev.42 is newer than 2.69.2", UpdateChecker.isNewer("2.69.3-dev.42", than: "2.69.2"), true)
    flag("2.69.3 is newer than 2.69.3-dev.42", UpdateChecker.isNewer("2.69.3", than: "2.69.3-dev.42"), true)
    flag("2.69.2 is NOT newer than 2.69.3-dev.42 (a development copy is never offered the release it is past)", UpdateChecker.isNewer("2.69.2", than: "2.69.3-dev.42"), false)
    flag("2.69.3-dev.100 is newer than 2.69.3-dev.42 (numbers compare as numbers)", UpdateChecker.isNewer("2.69.3-dev.100", than: "2.69.3-dev.42"), true)
    flag("2.69.3-dev.42+aaaaaaa vs 2.69.3-dev.42+bbbbbbb: build metadata is ignored", UpdateChecker.isNewer("2.69.3-dev.42+aaaaaaa", than: "2.69.3-dev.42+bbbbbbb"), false)
    flag("2.69.3-dev.1 is newer than 2.69.3-dev", UpdateChecker.isNewer("2.69.3-dev.1", than: "2.69.3-dev"), true)
    flag("2.70.0 is newer than 2.69.3 (a development copy is offered the next real release)", UpdateChecker.isNewer("2.70.0", than: "2.69.3-dev.42"), true)
    flag("2.10.0 is newer than 2.9.0", UpdateChecker.isNewer("2.10.0", than: "2.9.0"), true)
    flag("equal is not newer", UpdateChecker.isNewer("2.69.2", than: "2.69.2"), false)

    // the version string is for display and for Releases: Beta and This Copy decide "newer" by commit and fingerprint
    let sameNumber = (UpdateChecker.compare("2.69.3-dev.42+aaaaaaa", "2.69.3-dev.42+bbbbbbb") == .orderedSame)
    flag("two development builds with the same -dev.N compare EQUAL by version", sameNumber, true)
    let betaDecision = ChannelLogic.beta(build: BuildInfo(release: "2.69.2", commitsAfter: 42, commit: "aaaaaaa" + String(repeating: "0", count: 33)),
                                         cloneBranch: "development", isClone: true, compare: BetaCompare(status: "ahead", aheadBy: 1))
    flag("   yet Beta still offers the newer commit (it decides by commit, not by the version string)", betaDecision.isUpdate, true)
    let copyDecision = ChannelLogic.thisCopy(build: BuildInfo(release: "2.69.2", commitsAfter: 42, commit: "aaaaaaa" + String(repeating: "0", count: 33), treeHash: "clean"),
                                             isClone: true, clone: CloneFacts(branch: "development", isDirty: true, fingerprint: "x", relation: .same))
    flag("   and This Copy still sees uncommitted work (it decides by commit and fingerprint)", copyDecision.isUpdate, true)

    print("\n— what the update state offers —")
    let dev = BuildInfo(release: "2.69.2", commitsAfter: 42, commit: commit)
    let onDev = UpdateState(build: dev)
    onDev.preset(latest: "2.69.2")
    flag("a development copy, latest release 2.69.2: nothing to install", onDev.isAvailable, false)
    flag("   and it reads as a development build, not up to date with a release it is past", onDev.summary == .developmentBuild, true)
    expect("   its installed version", onDev.installed, "2.69.3-dev.42+8e2c9b0")
    let onDev2 = UpdateState(build: dev)
    onDev2.preset(latest: "2.69.3")
    flag("the same copy once 2.69.3 is published: offered on the Releases channel (2.69.3-dev.42 sorts below 2.69.3)", onDev2.isAvailable, true)
    expect("   the footer button", onDev2.availableTitle ?? "none", "Update to v2.69.3")
    let onRelease = UpdateState(build: BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit))
    onRelease.preset(latest: "2.69.2")
    flag("a release copy on the latest release: up to date", onRelease.summary == .upToDate && !onRelease.isAvailable, true)

    print("\n— the owner's flow: This Copy, Check Now, Rebuild —")
    let root = ProbeScratch.folder("ma-probe-versions")
    func git(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=probe", "-c", "user.email=probe@example.invalid", "-c", "commit.gpgsign=false", "-C", root.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run(); process.waitUntilExit()
    }
    func head() -> String {
        let process = Process(); let out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = ["-C", root.path, "rev-parse", "HEAD"]
        process.standardOutput = out; try? process.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit(); return text
    }
    git(["init", "-q", "-b", "development"])
    try? "one\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    git(["add", "-A"]); git(["commit", "-q", "-m", "first"])
    let built = head()
    UserDefaults.standard.removeObject(forKey: UpdateChannel.defaultsKey)
    let flowBuild = BuildInfo(release: "2.69.2", commitsAfter: 1, localChanges: false, commit: built, branch: "development", treeHash: "clean")
    let flow = UpdateState(build: flowBuild, clone: { SourceClone(root: root) })
    flow.channel = .thisCopy
    await flow.check(force: true)
    flag("clone equals the installed build: up to date", flow.channelState == .upToDate && !flow.isAvailable, true)
    flag("   the picker offers Releases, Beta and This Copy for a clone on development", flow.channels == [.releases, .beta, .thisCopy], true)
    try? "two\n".write(to: root.appending(path: "b.txt"), atomically: true, encoding: .utf8)
    git(["add", "-A"]); git(["commit", "-q", "-m", "second"])
    try? "uncommitted\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    await flow.check(force: true)
    flag("Check Now after a commit and an edit: newer work in the clone", flow.channelState == .behind(changes: 1, uncommitted: true) && flow.isAvailable, true)
    expect("   the sentence", flow.channelState?.sentence(for: .thisCopy) ?? "", "Your clone has 1 commit that is not in this copy, and changes that are not committed yet.")
    expect("   the button", flow.availableTitle ?? "none", Names.Channel.rebuild)
    expect("   the sidebar says", String(describing: flow.summary), "Optional(AnalyzersKit.UpdateState.Summary.updateAvailable)")
    let rebuild = root.deletingLastPathComponent()      // unused: the script lives in the repository, not the throwaway clone
    _ = rebuild
    let scripts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let command = scripts.appending(path: "rebuild.command").path
    let text = (try? String(contentsOfFile: command, encoding: .utf8)) ?? ""
    flag("rebuild.command exists, is executable and runs upgrade.command --no-pull (the build without the pull)",
         FileManager.default.isExecutableFile(atPath: command) && text.contains("exec ./upgrade.command --no-pull"), true)
    let upgrade = (try? String(contentsOfFile: scripts.appending(path: "upgrade.command").path, encoding: .utf8)) ?? ""
    flag("upgrade.command skips `git pull` under --no-pull", upgrade.contains("--no-pull") && upgrade.contains("if [[ \"$pull\" -eq 1 ]]"), true)
    UserDefaults.standard.removeObject(forKey: UpdateChannel.defaultsKey)

    // a check started for one channel never shows its answer under another
    let raceBuild = BuildInfo(release: "2.69.2", commitsAfter: 1, commit: built, branch: "development", treeHash: "clean")
    let race = UpdateState(build: raceBuild, clone: { Thread.sleep(forTimeInterval: 0.4); return SourceClone(root: root) })
    race.channel = .thisCopy                  // starts a check for This Copy, which is slow ...
    try? await Task.sleep(for: .milliseconds(100))
    race.channel = .releases                  // ... and the person switches before it answers
    try? await Task.sleep(for: .seconds(2.5))
    flag("a slow This Copy check that finishes after the switch to Releases shows nothing under Releases",
         race.channel == .releases && race.channelState == nil && race.cloneFacts == nil, true)
    UserDefaults.standard.removeObject(forKey: UpdateChannel.defaultsKey)

    print("\n\(failed == 0 ? "all version rules hold" : "\(failed) version rule(s) broken")")
    ProbeScratch.finish(failed == 0 ? 0 : 1)
}
