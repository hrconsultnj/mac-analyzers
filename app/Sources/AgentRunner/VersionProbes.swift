@_spi(TestSupport) import AnalyzersKit
import Foundation

/// `agent-runner --probe-versions`: what version a build IS, what a person reads for it, and how versions
/// compare. A build exactly at its release tag with a clean tree is that release ("2.72.0"); a clean build at a
/// `vX.Y.Z-beta.N` tag is that beta ("2.72.1 Beta"); any other build from a clone is "Dev · <short commit>".
/// Inside, the full semantic-versioning string orders them (2.72.0 < 2.72.1-beta.1 < 2.72.1-dev.N < 2.72.1), so a
/// copy is never offered what it is already past. Also proves which versions the Beta channel offers (a beta is
/// never offered on Releases, a newer release is offered on Beta) and runs the owner's flow on a throwaway
/// clone: This Copy, Check Now, what is newer in the clone, and the Rebuild button.
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

    print("— the version of a build (inside) —")
    expect("at the tag, clean tree", BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit).version, "2.69.2")
    expect("at the tag, uncommitted changes", BuildInfo(release: "2.69.2", commitsAfter: 0, localChanges: true, commit: commit).version, "2.69.3-dev.0+8e2c9b0.local")
    expect("42 commits after the tag", BuildInfo(release: "2.69.2", commitsAfter: 42, commit: commit).version, "2.69.3-dev.42+8e2c9b0")
    expect("42 commits after the tag, uncommitted changes", BuildInfo(release: "2.69.2", commitsAfter: 42, localChanges: true, commit: commit).version, "2.69.3-dev.42+8e2c9b0.local")
    expect("no release tag in reach (a clone, no count)", BuildInfo(release: "2.69.2", commitsAfter: nil, commit: commit).version, "2.69.3-dev+8e2c9b0")
    expect("no release tag in reach, uncommitted changes", BuildInfo(release: "2.69.2", commitsAfter: nil, localChanges: true, commit: commit).version, "2.69.3-dev+8e2c9b0.local")
    expect("not a clone (a download: no stamp)", BuildInfo(release: "2.69.2", commitsAfter: nil).version, "2.69.2")
    expect("git could not say whether the tree was clean: the version says so, never silently clean",
           BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit, treeHash: "unknown").version, "2.69.3-dev.0+8e2c9b0.unknown")
    expect("   (and it is not a release)", String(BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit, treeHash: "unknown").isDevelopment), "true")
    // VERSION ahead of the newest tag in the clone (bumped before the release is tagged, or the tag not fetched):
    // the build is heading TO that release, not past it
    let early = BuildInfo(release: "2.70.0", commitsAfter: 15, commit: "abcdef1" + String(repeating: "0", count: 33), releaseTag: "v2.69.2")
    expect("VERSION 2.70.0 but the newest tag found is v2.69.2: the base is VERSION itself", early.version, "2.70.0-dev.15+abcdef1")
    flag("   so 2.70.0 is still offered when it is published", UpdateChecker.isNewer("2.70.0", than: early.version), true)
    flag("   and the build is above the release before it", UpdateChecker.isNewer(early.version, than: "2.69.2"), true)
    expect("the tag of VERSION itself was found: the next patch as before",
           BuildInfo(release: "2.70.0", commitsAfter: 15, commit: "abcdef1" + String(repeating: "0", count: 33), releaseTag: "v2.70.0").version, "2.70.1-dev.15+abcdef1")
    expect("the next patch after a minor", BuildInfo.nextPatch(after: "2.70.0"), "2.70.1")

    print("\n— what a person reads —")
    let release = BuildInfo(release: "2.72.0", commitsAfter: 0, commit: commit, releaseTag: "v2.72.0")
    expect("a release is just its number", release.label, "2.72.0")
    expect("   the Updates screen", release.versionText, "v2.72.0")
    expect("   the sidebar", release.sidebarText, "Version 2.72.0")
    expect("   the menu footer", release.shortVersionText, "v2.72.0")
    expect("   the About panel", release.shortVersion, "2.72.0")
    let beta1 = BuildInfo(release: "2.72.0", commitsAfter: 6, commit: commit, treeHash: "clean", releaseTag: "v2.72.0", betaTag: "v2.72.1-beta.1")
    expect("the first beta of 2.72.1", beta1.label, "2.72.1 Beta")
    expect("   the Updates screen", beta1.versionText, "v2.72.1 Beta")
    expect("   the sidebar", beta1.sidebarText, "Version 2.72.1 Beta")
    expect("   the menu footer", beta1.shortVersionText, "v2.72.1 Beta")
    expect("   inside, the full version", beta1.version, "2.72.1-beta.1")
    flag("   a beta is not a development build", beta1.isDevelopment, false)
    flag("   and it is a beta", beta1.isBeta, true)
    let beta2 = BuildInfo(release: "2.72.0", commitsAfter: 9, commit: commit, treeHash: "clean", releaseTag: "v2.72.0", betaTag: "v2.72.1-beta.2")
    expect("the second beta of 2.72.1 carries its number", beta2.label, "2.72.1 Beta 2")
    expect("   in the sidebar", beta2.sidebarText, "Version 2.72.1 Beta 2")
    expect("the tenth beta", BuildInfo(release: "2.72.0", commitsAfter: 9, commit: commit, treeHash: "clean", releaseTag: "v2.72.0", betaTag: "v2.72.1-beta.10").label, "2.72.1 Beta 10")
    let dirtyBeta = BuildInfo(release: "2.72.0", commitsAfter: 6, localChanges: true, commit: commit, treeHash: String(repeating: "a", count: 64), releaseTag: "v2.72.0", betaTag: "v2.72.1-beta.1")
    expect("a beta built with uncommitted changes is a Dev copy, not the beta", dirtyBeta.label, "Dev · 8e2c9b0*")
    flag("   and a development build", dirtyBeta.isDevelopment && !dirtyBeta.isBeta, true)
    expect("   unknown tree: not provably the beta either", BuildInfo(release: "2.72.0", commitsAfter: 6, commit: commit, treeHash: "unknown", releaseTag: "v2.72.0", betaTag: "v2.72.1-beta.1").label, "Dev · 8e2c9b0?")
    expect("a tag that is not a beta is not stamped as one", String(describing: BuildInfo(release: "2.72.0", commitsAfter: 1, commit: commit, releaseTag: "v2.72.0", betaTag: "v2.72.1-rc1").betaTag), "nil")
    let dev = BuildInfo(release: "2.72.0", commitsAfter: 12, commit: commit, releaseTag: "v2.72.0")
    expect("a copy built from a clone with commits after the tag", dev.label, "Dev · 8e2c9b0")
    expect("   the Updates screen", dev.versionText, "Dev · 8e2c9b0")
    expect("   the sidebar", dev.sidebarText, "Dev · 8e2c9b0")
    expect("   the menu footer", dev.shortVersionText, "Dev · 8e2c9b0")
    expect("uncommitted changes add one short mark", BuildInfo(release: "2.72.0", commitsAfter: 0, localChanges: true, commit: commit, releaseTag: "v2.72.0").label, "Dev · 8e2c9b0*")
    expect("a build that never recorded its commit says only Dev", BuildInfo(release: "2.72.0", commitsAfter: 5).label, "Dev")
    expect("a download is a release", BuildInfo(release: "2.72.0", commitsAfter: nil).label, "2.72.0")
    let everything = [release, beta1, beta2, dirtyBeta, dev,
                      BuildInfo(release: "2.72.0", commitsAfter: 12, localChanges: true, commit: commit, releaseTag: "v2.72.0")]
        .flatMap { [$0.label, $0.versionText, $0.shortVersionText, $0.sidebarText, $0.shortVersion] }
    flag("no \"-dev\", \"-beta\" or \"+hash\" string appears in anything a person reads (\(everything.count) strings)",
         !everything.contains { $0.contains("-dev") || $0.contains("-beta") || $0.contains("+") }, true)
    expect("a version string becomes its name in one place", BuildInfo.label(forVersion: "2.73.0-dev.3+abc1234.local"), "Dev · abc1234*")

    print("\n— semantic-versioning precedence —")
    flag("2.69.3-dev.42 is newer than 2.69.2", UpdateChecker.isNewer("2.69.3-dev.42", than: "2.69.2"), true)
    flag("2.69.3 is newer than 2.69.3-dev.42", UpdateChecker.isNewer("2.69.3", than: "2.69.3-dev.42"), true)
    flag("2.69.2 is NOT newer than 2.69.3-dev.42 (a development copy is never offered the release it is past)", UpdateChecker.isNewer("2.69.2", than: "2.69.3-dev.42"), false)
    flag("2.69.3-dev.100 is newer than 2.69.3-dev.42 (numbers compare as numbers)", UpdateChecker.isNewer("2.69.3-dev.100", than: "2.69.3-dev.42"), true)
    flag("2.69.3-dev.42+aaaaaaa vs 2.69.3-dev.42+bbbbbbb: build metadata is ignored", UpdateChecker.isNewer("2.69.3-dev.42+aaaaaaa", than: "2.69.3-dev.42+bbbbbbb"), false)
    flag("2.69.3-dev.1 is newer than 2.69.3-dev", UpdateChecker.isNewer("2.69.3-dev.1", than: "2.69.3-dev"), true)
    flag("2.70.0 is newer than 2.69.3 (a development copy is offered the next real release)", UpdateChecker.isNewer("2.70.0", than: "2.69.3-dev.42"), true)
    flag("2.10.0 is newer than 2.9.0", UpdateChecker.isNewer("2.10.0", than: "2.9.0"), true)
    flag("a beta is above the release before it", UpdateChecker.isNewer("2.72.1-beta.1", than: "2.72.0"), true)
    flag("a beta is below the release it leads to", UpdateChecker.isNewer("2.72.1", than: "2.72.1-beta.9"), true)
    flag("beta.10 is above beta.2 (numbers compare as numbers)", UpdateChecker.isNewer("2.72.1-beta.10", than: "2.72.1-beta.2"), true)
    flag("a development copy of 2.72.1 is past its betas", UpdateChecker.isNewer("2.72.1-dev.3", than: "2.72.1-beta.2"), true)
    flag("equal is not newer", UpdateChecker.isNewer("2.69.2", than: "2.69.2"), false)

    // Releases and Beta decide by version; This Copy decides by commit and fingerprint
    let sameNumber = (UpdateChecker.compare("2.69.3-dev.42+aaaaaaa", "2.69.3-dev.42+bbbbbbb") == .orderedSame)
    flag("two development builds with the same -dev.N compare EQUAL by version", sameNumber, true)
    let copyDecision = ChannelLogic.thisCopy(build: BuildInfo(release: "2.69.2", commitsAfter: 42, commit: "aaaaaaa" + String(repeating: "0", count: 33), treeHash: "clean"),
                                             isClone: true, clone: CloneFacts(branch: "development", isDirty: true, fingerprint: "x", relation: .same))
    flag("   and This Copy still sees uncommitted work (it decides by commit and fingerprint)", copyDecision.isUpdate, true)

    print("\n— what the update state offers —")
    let oldDev = BuildInfo(release: "2.69.2", commitsAfter: 42, commit: commit)
    let onDev = UpdateState(build: oldDev)
    onDev.preset(latest: "2.69.2")
    flag("a development copy, latest release 2.69.2: nothing to install", onDev.isAvailable, false)
    flag("   and it reads as a development build, not up to date with a release it is past", onDev.summary == .developmentBuild, true)
    expect("   its installed version", onDev.installed, "2.69.3-dev.42+8e2c9b0")
    let onDev2 = UpdateState(build: oldDev)
    onDev2.preset(latest: "2.69.3")
    flag("the same copy once 2.69.3 is published: offered on the Releases channel (2.69.3-dev.42 sorts below 2.69.3)", onDev2.isAvailable, true)
    expect("   the footer button", onDev2.availableTitle ?? "none", "Update to v2.69.3")
    let onRelease = UpdateState(build: BuildInfo(release: "2.69.2", commitsAfter: 0, commit: commit))
    onRelease.preset(latest: "2.69.2")
    flag("a release copy on the latest release: up to date", onRelease.summary == .upToDate && !onRelease.isAvailable, true)

    print("\n— Beta: the newest pre-release —")
    // GitHub's list, as it answers: pre-releases and releases together, newest first, plus what is not either
    let listing = """
    [{"tag_name":"v2.72.1-beta.2","prerelease":true,"draft":false},
     {"tag_name":"v2.72.1-beta.10","prerelease":true,"draft":false},
     {"tag_name":"v2.72.1-beta.1","prerelease":true,"draft":false},
     {"tag_name":"v2.73.0-beta.1","prerelease":true,"draft":true},
     {"tag_name":"v2.72.2-rc1","prerelease":true,"draft":false},
     {"tag_name":"v2.72.0","prerelease":false,"draft":false},
     {"tag_name":"v2.71.0","prerelease":false,"draft":false}]
    """
    let fixtureFeed = BetaFeed.parse(releases: Data(listing.utf8))
    expect("the newest beta is the highest beta number; drafts and other tags are ignored", fixtureFeed?.newestBeta ?? "none", "2.72.1-beta.10")
    expect("the newest release is the newest that is not a pre-release", fixtureFeed?.newestRelease ?? "none", "2.72.0")
    expect("   Beta offers the beta", fixtureFeed?.target ?? "none", "2.72.1-beta.10")
    let onlyBeta = BetaFeed.parse(releases: Data(#"[{"tag_name":"v2.72.1-beta.1","prerelease":true,"draft":false}]"#.utf8))
    expect("a pre-release is never the newest RELEASE (what the update notification and Releases read)", onlyBeta?.newestRelease ?? "none", "none")
    flag("a list that is not a list is not an answer", BetaFeed.parse(releases: Data("{}".utf8)) == nil, true)
    func beta(_ build: BuildInfo, _ feed: BetaFeed?, branch: String? = "development", clone: Bool = true) -> ChannelState {
        ChannelLogic.beta(build: build, cloneBranch: branch, isClone: clone, feed: feed)
    }
    let published = BetaFeed(newestBeta: "2.72.1-beta.1", newestRelease: "2.72.0")
    let secondBeta = BetaFeed(newestBeta: "2.72.1-beta.2", newestRelease: "2.72.0")
    let shipped = BetaFeed(newestBeta: "2.72.1-beta.2", newestRelease: "2.72.1")
    let none = BetaFeed(newestBeta: nil, newestRelease: "2.72.0")
    func state(_ label: String, _ got: ChannelState, _ expected: ChannelState, says: String? = nil) {
        let ok = got == expected && (says == nil || got.sentence(for: .beta) == says)
        if !ok { failed += 1 }
        print("\(ok ? "PASS" : "FAIL") \(label): \(got.sentence(for: .beta))" + (ok ? "" : "   (expected \(expected))"))
    }
    state("a release copy is offered the first beta", beta(release, published), .offered("2.72.1 Beta"), says: "2.72.1 Beta is available.")
    state("beta 1 is offered beta 2", beta(beta1, secondBeta), .offered("2.72.1 Beta 2"), says: "2.72.1 Beta 2 is available.")
    state("beta 2 on beta 2 is the newest beta", beta(beta2, secondBeta), .upToDate, says: "You have the newest beta.")
    state("a release newer than the beta is offered on Beta too", beta(beta2, shipped), .offered("2.72.1"), says: "2.72.1 is available.")
    state("   including to a release copy", beta(release, shipped), .offered("2.72.1"))
    state("no beta out and this copy is the newest release: say so plainly", beta(release, none), .unavailable(Names.ChannelText.noBetaYet))
    state("a Dev copy of 2.72.1 is past the betas", beta(dev, secondBeta), .ahead(Names.ChannelText.aheadOfBeta))
    // by version a Dev copy of 2.72.1 is above every beta of it: whether it HOLDS the newest one is asked by commit
    state("a Dev copy that lacks the newest beta is offered it (the version cannot say)", ChannelLogic.beta(build: dev, cloneBranch: "development", isClone: true, feed: secondBeta, containment: .lacks), .offered("2.72.1 Beta 2"))
    state("a Dev copy that holds the newest beta is ahead of it", ChannelLogic.beta(build: dev, cloneBranch: "development", isClone: true, feed: secondBeta, containment: .contains), .ahead(Names.ChannelText.aheadOfBeta))
    state("a Dev copy whose commit could not be compared is never offered what it may hold", ChannelLogic.beta(build: dev, cloneBranch: "development", isClone: true, feed: secondBeta, containment: nil), .ahead(Names.ChannelText.aheadOfBeta))
    state("containment is not asked of a release copy: the version decides", ChannelLogic.beta(build: release, cloneBranch: "development", isClone: true, feed: secondBeta, containment: .contains), .offered("2.72.1 Beta 2"))
    state("a Dev copy with no beta out is past the release", beta(dev, none), .ahead(Names.ChannelText.aheadOfRelease))
    state("a Dev copy is still offered a release newer than itself", beta(dev, BetaFeed(newestBeta: "2.72.1-beta.2", newestRelease: "2.72.1")), .offered("2.72.1"))
    state("offline: nothing answered", beta(release, nil), .unknown(Names.ChannelText.offline))
    state("rate limited", beta(release, BetaFeed(status: "rateLimited")), .unknown(Names.ChannelText.rateLimited))
    state("a clone on another branch cannot follow", beta(release, published, branch: "main"), .unavailable(Names.ChannelText.notOnDevelopment("main")))
    state("a download cannot follow", beta(release, published, branch: nil, clone: false), .unavailable(Names.ChannelText.notAClone))
    // Releases never sees a beta: it reads the release only, so a beta copy and a release copy compare by release
    let relRel = UpdateState(build: release); relRel.preset(latest: "2.72.0")
    flag("Releases: nothing is offered to a release copy while only a beta is newer", !relRel.isAvailable, true)
    let betaOnReleases = UpdateState(build: beta2); betaOnReleases.preset(latest: "2.72.0")
    flag("Releases: a beta copy is not offered the release it is past", !betaOnReleases.isAvailable, true)
    let betaThenRelease = UpdateState(build: beta2); betaThenRelease.preset(latest: "2.72.1")
    flag("Releases: the release that follows a beta is offered to it", betaThenRelease.isAvailable, true)
    let offeredState = UpdateState(build: release)
    offeredState.preset(channel: .beta, state: beta(release, published), newest: "2.72.1 Beta")
    flag("Beta: the footer and sidebar see an update", offeredState.isAvailable && offeredState.summary == .updateAvailable, true)
    expect("   the footer button", offeredState.availableTitle ?? "none", Names.Channel.installBeta)
    let currentBeta = UpdateState(build: beta2)
    currentBeta.preset(channel: .beta, state: beta(beta2, secondBeta), newest: "2.72.1 Beta 2")
    flag("Beta: a beta copy on the newest beta is up to date", currentBeta.summary == .upToDate && !currentBeta.isAvailable, true)

    print("\n— tags: a beta is never a release —")
    let tagRoot = ProbeScratch.folder("ma-probe-tags")
    func tagGit(_ arguments: [String]) -> String {
        let process = Process(); let out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=probe", "-c", "user.email=probe@example.invalid", "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", "-C", tagRoot.path] + arguments
        process.standardOutput = out; process.standardError = FileHandle.nullDevice
        try? process.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit(); return text
    }
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    func tagScript(_ arguments: [String]) -> String {
        let process = Process(); let out = Pipe()
        process.executableURL = repoRoot.appending(path: "app/release-tag.sh")
        process.arguments = arguments
        process.standardOutput = out; process.standardError = FileHandle.nullDevice
        try? process.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit(); return text
    }
    _ = tagGit(["init", "-q", "-b", "development"])
    for (name, tag) in [("one", "v2.72.0"), ("two", nil), ("three", "v2.72.1-beta.1")] as [(String, String?)] {
        try? (name + "\n").write(to: tagRoot.appending(path: name + ".txt"), atomically: true, encoding: .utf8)
        _ = tagGit(["add", "-A"]); _ = tagGit(["commit", "-q", "-m", name])
        if let tag { _ = tagGit(["tag", tag]) }
    }
    expect("release counting ignores the beta tag: 2 commits after v2.72.0 at the beta's commit", tagScript([tagRoot.path, "2.72.0"]), "v2.72.0 2")
    expect("the beta stamp is found at the beta's commit", tagScript(["--beta", tagRoot.path]), "v2.72.1-beta.1")
    _ = tagGit(["tag", "-d", "v2.72.0"])
    expect("with the release tag gone, the nearest tag is never the beta (nothing is counted)", tagScript([tagRoot.path, "2.72.1"]), "")
    try? "four\n".write(to: tagRoot.appending(path: "four.txt"), atomically: true, encoding: .utf8)
    _ = tagGit(["add", "-A"]); _ = tagGit(["commit", "-q", "-m", "four"])
    expect("a commit after the beta is not the beta", tagScript(["--beta", tagRoot.path]), "")

    print("\n— update choices, the update window's notes and the status card —")
    UpdateChoicesProbe.run { label, ok, detail in
        if !ok { failed += 1 }
        print("\(ok ? "PASS" : "FAIL") \(label)\(ok || detail.isEmpty ? "" : "   (\(detail))")")
    }

    print("\n— the install scripts, run for real on a scratch clone —")
    UpgradeScriptProbe.run(repoRoot: repoRoot) { label, ok, detail in
        if !ok { failed += 1 }
        print("\(ok ? "PASS" : "FAIL") \(label)\(ok || detail.isEmpty ? "" : "   (\(detail))")")
    }
    flag("beta.command exists and is executable", FileManager.default.isExecutableFile(atPath: repoRoot.appending(path: "beta.command").path), true)

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
