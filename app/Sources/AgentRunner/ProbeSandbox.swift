import Foundation
@_spi(TestSupport) import AnalyzersKit

/// What a probe that judges itself may read: the checkout it was built from, and nothing of the person's.
///
/// A gate that runs from the person's own checkout (the pre-push hook and `cut-release.sh` do) reaches a home
/// with their settings, their logs and a copy of the engine that may be older or newer than the code under
/// test. A probe whose answer depends on any of that passes on one Mac and fails on another, or passes only
/// because a file it needed was missing (the cleanup probe did exactly that: its stand-in programs were
/// "kept" as soon as the person's coding-agent list existed and the gate ran under a coding session).
///
/// So these probes (1) run with a throwaway home (`AnalyzersPaths.useHome`, and HOME for what they start), set before anything resolves a path, (2) refuse to start,
/// with a sentence, if their home or suite root still resolves into the person's real home, and (3) find
/// the checkout from where THEY WERE BUILT, never from the folder they are run in, so the output is the
/// same from the worktree, from the person's checkout and from `/tmp`.
enum ProbeSandbox {

    /// The probes that run in the sandbox.
    static let names: Set<String> = ["--probe-cleanup-apply", "--probe-agents", "--probe-guard-rules", "--probe-stop-targets", "--probe-activity-ids"]

    /// The repository this binary was built from: `…/app/Sources/AgentRunner/ProbeSandbox.swift` is four levels down.
    static let sourceRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }()

    // written once, before anything else runs, and read once by the exit handler (a C function pointer cannot
    // capture state): there is no concurrent access to guard
    nonisolated(unsafe) private static var throwawayHome: String?

    /// The account's real home folder, from the account database (the environment can be changed by whoever starts us).
    static var realHome: String {
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }

    static func enter(_ probe: String) {
        let real = URL(fileURLWithPath: realHome).resolvingSymlinksInPath().path
        let home = FileManager.default.temporaryDirectory.appending(path: "ma-probe-home-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        throwawayHome = home.path
        atexit { if let path = ProbeSandbox.throwawayHome { try? FileManager.default.removeItem(atPath: path) } }
        AnalyzersPaths.useHome(home)
        setenv("HOME", home.path, 1)        // and whatever the probe starts

        let resolved = AnalyzersPaths.home.resolvingSymlinksInPath().path
        let suite = AnalyzersPaths.suiteRoot.resolvingSymlinksInPath().path
        guard resolved != real, !resolved.hasPrefix(real + "/"), suite != real, !suite.hasPrefix(real + "/") else {
            print("\(probe) was not run: its home folder (\(resolved)) or suite root (\(suite)) resolves into your own home, "
                  + "and this probe must not read or write anything of yours.")
            exit(2)
        }
    }
}
