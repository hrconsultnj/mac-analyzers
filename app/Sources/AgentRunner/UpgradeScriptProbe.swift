import Foundation

/// `--probe-versions`, the install half: RUNS `beta.command` and `upgrade.command --beta` on a scratch clone, under the
/// bash macOS ships and under a newer one when this Mac has one, in a UTF-8 locale, and judges where the clone ends.
/// (A text search of the script once passed a defect that stopped every beta install, a variable name that swallowed the
/// first byte of the "…" after it under `set -u`; only running it shows that class.)
///
/// The world is a bare "origin" with a release tag, two beta tags (only the first has a published pre-release, which the
/// script asks of a stand-in API folder through `MA_GITHUB_API`), a later release and a development tip, and a clone on
/// development. The build, the agents' installers and everything that touches the running app (pgrep, pkill, osascript,
/// open, sleep) are stubs, so nothing real is built, stopped or launched.
enum UpgradeScriptProbe {

    static func run(repoRoot: URL, report: (String, Bool, String) -> Void) {
        let shells = ["/bin/bash", "/opt/homebrew/bin/bash", "/usr/local/bin/bash"].filter { FileManager.default.isExecutableFile(atPath: $0) }
        for shell in shells {
            let world = World(repoRoot: repoRoot, tag: shell.replacingOccurrences(of: "/", with: "-"))
            let name = shell == "/bin/bash" ? "bash 3.2 (/bin/bash)" : shell
            world.reset(to: world.c1)
            var result = world.run(shell, "beta.command")
            report("\(name): beta.command moves the clone to the newest PUBLISHED beta (the bare tag after it is skipped)",
                   result.status == 0 && world.head() == world.c2, "exit \(result.status), clone at \(world.label(world.head())): \(result.tail)")
            report("\(name):   and the build ran on exactly that commit", world.built() == world.c2, "built: \(world.label(world.built() ?? ""))")

            world.publishRelease()
            world.reset(to: world.c2)
            result = world.run(shell, "beta.command")
            report("\(name): once the release is out, the clone moves to the release TAG, not the development tip",
                   result.status == 0 && world.head() == world.c4, "exit \(result.status), clone at \(world.label(world.head())): \(result.tail)")

            world.reset(to: world.c5)
            result = world.run(shell, "beta.command")
            report("\(name): a clone already past the newest version is refused and left where it was",
                   result.status == 1 && world.head() == world.c5 && result.output.contains("already past") && world.built() == nil,
                   "exit \(result.status), clone at \(world.label(world.head())): \(result.tail)")
            world.reset(to: world.c5)
            result = world.run(shell, "upgrade.command", args: ["--release"])
            report("\(name): choosing the release checks it out even when the clone is past it, and development stays put",
                   result.status == 0 && world.head() == world.c4 && world.tip("development") == world.c5,
                   "exit \(result.status), clone at \(world.label(world.head())), development at \(world.label(world.tip("development"))): \(result.tail)")
            world.unpublishRelease()
            // Still detached on the release. Double-click beta.command must refuse; choosing Beta must check it out.
            result = world.run(shell, "beta.command")
            report("\(name): beta.command still refuses a clone that is not on the development branch",
                   result.status == 1 && world.head() == world.c4 && result.output.contains("another branch"),
                   "exit \(result.status), clone at \(world.label(world.head())): \(result.tail)")
            // The stub build records .built inside the clone. That file is untracked here
            // (the real build's products are gitignored) and must not count as the person's work.
            world.clearBuilt()
            result = world.run(shell, "upgrade.command", args: ["--beta", "--switch"])
            report("\(name): choosing the beta checks it out even when the clone is past it and detached",
                   result.status == 0 && world.head() == world.c2 && world.tip("development") == world.c5,
                   "exit \(result.status), clone at \(world.label(world.head())), development at \(world.label(world.tip("development"))): \(result.tail)")
            world.reset(to: world.c5)
            result = world.run(shell, "upgrade.command", args: ["--beta", "--switch"])
            report("\(name): choosing the beta checks it out from the development branch when the clone is past it",
                   result.status == 0 && world.head() == world.c2 && world.tip("development") == world.c5,
                   "exit \(result.status), clone at \(world.label(world.head())), development at \(world.label(world.tip("development"))): \(result.tail)")

            // GitHub cannot be asked (nothing listens there): that is "couldn't reach", never "nothing is published"
            world.reset(to: world.c1)
            result = world.run(shell, "beta.command", api: "http://127.0.0.1:1")
            report("\(name): a failed request to GitHub says it could not reach GitHub, and changes nothing",
                   result.status == 1 && world.head() == world.c1 && result.output.contains("Could not reach GitHub")
                   && !result.output.contains("No published"), "exit \(result.status): \(result.tail)")
        }
        if shells.count == 1 { report("a newer bash was not found on this Mac: only /bin/bash ran", true, "") }
    }

    private final class World {
        let root: URL, origin: URL, clone: URL, api: URL, stubs: URL
        let repoRoot: URL
        var c1 = "", c2 = "", c3 = "", c4 = "", c5 = ""

        init(repoRoot: URL, tag: String) {
            self.repoRoot = repoRoot
            root = ProbeScratch.folder("ma-probe-upgrade\(tag)")
            origin = root.appending(path: "origin.git")
            clone = root.appending(path: "clone")
            api = root.appending(path: "api")
            stubs = root.appending(path: "stubs")
            let seed = root.appending(path: "seed")
            let fm = FileManager.default
            for dir in [api.appending(path: "releases/tags"), stubs, seed] { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            _ = git(root, ["init", "-q", "--bare", "-b", "development", origin.path])
            _ = git(seed, ["init", "-q", "-b", "development"])
            _ = git(seed, ["remote", "add", "origin", origin.path])
            // the real scripts, as they are in the repository, and stubs for everything else the upgrade runs
            for file in ["upgrade.command", "beta.command"] {
                try? fm.copyItem(at: repoRoot.appending(path: file), to: seed.appending(path: file))
            }
            write(seed, "VERSION", "2.72.0\n", executable: false)
            // The real repository ignores the built app. This scratch clone must too,
            // or the stub agent-runner looks like the person's uncommitted work.
            write(seed, ".gitignore", ".built\napp/Sparehold.app/\n", executable: false)
            write(seed, "app/build.sh", """
#!/bin/sh
echo "installed: stub"
root="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$root" rev-parse HEAD > "$root/.built"
mkdir -p "$root/app/Sparehold.app/Contents/MacOS"
printf '%s\\n' '#!/bin/sh' 'echo "Installed Version: vstub"' > "$root/app/Sparehold.app/Contents/MacOS/agent-runner"
chmod +x "$root/app/Sparehold.app/Contents/MacOS/agent-runner"
""")
            write(seed, "memory/memory-manage-agents.sh", "#!/bin/sh\nexit 0\n")
            write(seed, "storage/storage-manage-agents.sh", "#!/bin/sh\nexit 0\n")
            func commit(_ n: String) -> String {
                write(seed, "n.txt", n + "\n", executable: false)
                _ = git(seed, ["add", "-A"]); _ = git(seed, ["commit", "-q", "-m", n])
                return git(seed, ["rev-parse", "HEAD"])
            }
            c1 = commit("one"); _ = git(seed, ["tag", "v2.72.0"])
            c2 = commit("two"); _ = git(seed, ["tag", "v2.72.1-beta.1"])
            c3 = commit("three"); _ = git(seed, ["tag", "v2.72.1-beta.2"])        // tagged, never published
            c4 = commit("four"); _ = git(seed, ["tag", "v2.72.1"])                  // published later in the probe
            c5 = commit("five")
            _ = git(seed, ["push", "-q", "origin", "development", "--tags"])
            for tag in ["v2.72.0", "v2.72.1-beta.1"] { try? "{}".write(to: api.appending(path: "releases/tags/\(tag)"), atomically: true, encoding: .utf8) }
            _ = git(root, ["clone", "-q", "-b", "development", origin.path, clone.path])
            // everything that would touch the real Mac does nothing
            for name in ["pgrep", "pkill", "osascript", "open", "sleep"] {
                write(stubs, name, name == "pgrep" ? "#!/bin/sh\nexit 1\n" : "#!/bin/sh\nexit 0\n", executable: true, plain: true)
            }
        }

        func write(_ base: URL, _ path: String, _ text: String, executable: Bool = true, plain: Bool = false) {
            let url = base.appending(path: path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            if executable { chmod(url.path, 0o755) }
        }

        func publishRelease() { try? "{}".write(to: api.appending(path: "releases/tags/v2.72.1"), atomically: true, encoding: .utf8) }
        func unpublishRelease() { try? FileManager.default.removeItem(at: api.appending(path: "releases/tags/v2.72.1")) }

        func clearBuilt() {
            let fm = FileManager.default
            try? fm.removeItem(at: clone.appending(path: ".built"))
            // The stub build leaves an agent-runner here so upgrade.command can
            // ask it the version. It is not the person's work, and it is not
            // gitignored in this scratch clone.
            try? fm.removeItem(at: clone.appending(path: "app/Sparehold.app"))
        }

        func reset(to commit: String) {
            // --release and --beta --switch detach HEAD. The next beta.command still
            // requires the development branch. reset --hard while detached stays detached.
            if git(clone, ["rev-parse", "--abbrev-ref", "HEAD"]) != "development" {
                _ = git(clone, ["checkout", "-q", "development"])
            }
            _ = git(clone, ["reset", "-q", "--hard", commit])
            clearBuilt()
        }
        func head() -> String { git(clone, ["rev-parse", "HEAD"]) }
        func built() -> String? {
            (try? String(contentsOf: clone.appending(path: ".built"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func label(_ commit: String) -> String {
            [c1: "c1 (v2.72.0)", c2: "c2 (beta.1)", c3: "c3 (beta.2, unpublished)", c4: "c4 (v2.72.1)", c5: "c5 (development tip)"][commit] ?? String(commit.prefix(7))
        }

        /// Runs `script` from the clone under `shell`, in a UTF-8 locale, with the stubs first on PATH.
        func tip(_ ref: String) -> String { git(clone, ["rev-parse", ref]) }

        func run(_ shell: String, _ script: String, args: [String] = [], api override: String? = nil) -> (status: Int32, output: String, tail: String) {
            let process = Process(); let out = Pipe()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = [clone.appending(path: script).path] + args
            process.currentDirectoryURL = clone
            process.environment = ["PATH": "\(stubs.path):/usr/bin:/bin:/usr/sbin:/sbin", "HOME": root.path,
                                   "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "MA_GITHUB_API": override ?? "file://\(api.path)",
                                   "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"]
            process.standardOutput = out; process.standardError = out
            process.standardInput = FileHandle.nullDevice
            try? process.run()
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let last = text.split(separator: "\n").suffix(2).joined(separator: " | ")
            return (process.terminationStatus, text, last)
        }

        @discardableResult
        func git(_ directory: URL, _ arguments: [String]) -> String {
            let process = Process(); let out = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-c", "user.name=probe", "-c", "user.email=probe@example.invalid", "-c", "commit.gpgsign=false",
                                 "-c", "tag.gpgsign=false", "-C", directory.path] + arguments
            process.standardOutput = out; process.standardError = FileHandle.nullDevice
            try? process.run()
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            process.waitUntilExit()
            return text
        }
    }
}
