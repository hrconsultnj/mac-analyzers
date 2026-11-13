import CryptoKit
import Foundation

/// Whether this Mac has the developer tools, and so a real `git`. On a Mac without them `/usr/bin/git` is
/// Apple's stub, and running it shows the "install the command line developer tools" dialog. The app never
/// runs it to find out: it asks `xcode-select -p`, which only prints, and looks for the tool it names.
enum GitTools {
    static let isInstalled: Bool = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        guard process.terminationStatus == 0, !path.isEmpty else { return false }
        return FileManager.default.isExecutableFile(atPath: path + "/usr/bin/git")
    }()
}

/// The git clone an installed copy was built from, read with plain local `git` commands. Nothing here
/// fetches, pulls or writes: a channel that needs the network asks GitHub's public API instead, and an
/// install is `upgrade.command`'s job, started by the person.
///
/// Reading a clone must never run a program the clone names. Git runs programs from configuration and
/// attributes while it reads (an fsmonitor hook on `status`, a clean filter on `diff`), so every call:
/// - turns the configuration that names a program off on the command line (`core.fsmonitor`,
///   `core.hooksPath`, `core.attributesFile`) and reads no attributes from the clone (`--attr-source` the
///   empty tree), no external diff and no text filter (`--no-ext-diff`, `--no-textconv` on the diff);
/// - gives git a minimal environment of its own: the person's global and system configuration are not
///   read at all (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM`), nor `GIT_ATTR_NOSYSTEM`'s file,
///   and no variable of the app's leaks in (`GIT_DIR` and friends);
/// - uses only commands that touch no remote, sign nothing and start no editor or pager
///   (`rev-parse`, `status`, `diff`, `ls-files`, `cat-file`, `merge-base`, `rev-list`), so
///   `credential.helper`, `core.sshCommand`, `gpg.program`, `uploadpack`/`receivepack` and the rest of the
///   keys that name a program are never reached; `include.path` and `includeIf` only load more
///   configuration, which the same command-line settings override.
/// `scripts/tree-hash.sh` makes the same calls; `agent-runner --probe-channels` proves a hostile clone
/// runs nothing.
///
/// A failure is never "clean": every reading that can fail returns nil, and the channel says "unknown".
public struct SourceClone: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// The clone this app belongs to: the suite root, when it is a git working tree, this Mac has the
    /// developer tools, and the root is the working tree's top level (not a folder inside a bigger
    /// repository, such as a home folder that is itself a clone). A downloaded app's root is inside its
    /// bundle: it runs no git at all.
    public static var current: SourceClone? {
        guard !AnalyzersPaths.usingBundledEngine, GitTools.isInstalled else { return nil }
        let clone = SourceClone(root: AnalyzersPaths.suiteRoot)
        return clone.isWorkingTree ? clone : nil
    }

    static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    /// The settings every call starts with (see the type's comment). Keep in step with scripts/tree-hash.sh.
    static let safeArguments = [
        "--no-optional-locks", "--no-pager", "--attr-source=\(emptyTree)",
        "-c", "core.fsmonitor=false", "-c", "core.useBuiltinFSMonitor=false",
        "-c", "core.hooksPath=/dev/null", "-c", "core.attributesFile=/dev/null",
    ]

    /// The environment of every call.
    static let environment: [String: String] = [
        "PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LC_ALL": "C",
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_ATTR_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
    ]

    /// Every filter and diff driver the clone's configuration defines, switched off on the command line.
    /// `--attr-source` keeps the clone's `.gitattributes` out, but `.git/info/attributes` is still read and can
    /// pick a driver, so a driver that names a program is emptied (git applies no filter for an empty command)
    /// and its `required` setting is cleared. `git config` only reads: it runs nothing.
    private func driverOverrides() -> [String] {
        var names = Data()
        guard run(["config", "--name-only", "--get-regexp", #"^(filter|diff)\..*\.(clean|smudge|process|textconv|command|required)$"#],
                  overrides: false, sink: { names.append($0) }) || names.isEmpty else { return [] }
        return String(decoding: names, as: UTF8.self).split(separator: "\n").flatMap { key -> [String] in
            ["-c", key.hasSuffix(".required") ? "\(key)=false" : "\(key)="]
        }
    }

    /// Runs `git` on the clone, handing what it prints to `sink` as it comes; false when it fails.
    @discardableResult
    private func run(_ arguments: [String], overrides: Bool = true, sink: (Data) -> Void) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = Self.safeArguments + (overrides ? driverOverrides() : []) + ["-C", root.path] + arguments
        process.environment = Self.environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        while case let chunk = out.fileHandleForReading.availableData, !chunk.isEmpty { sink(chunk) }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// What git printed, or nil when it failed.
    private func git(_ arguments: [String]) -> Data? {
        var data = Data()
        return run(arguments) { data.append($0) } ? data : nil
    }

    private func text(_ arguments: [String]) -> String? {
        git(arguments).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// A working tree whose top level is this folder.
    public var isWorkingTree: Bool {
        guard text(["rev-parse", "--is-inside-work-tree"]) == "true",
              let top = text(["rev-parse", "--show-toplevel"]) else { return false }
        return URL(fileURLWithPath: top).resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path
    }

    /// The branch, nil on a detached head.
    public var branch: String? {
        guard let name = text(["rev-parse", "--abbrev-ref", "HEAD"]), name != "HEAD" else { return nil }
        return name
    }

    public var head: String? { text(["rev-parse", "HEAD"]) }

    /// Whether anything is uncommitted, untracked files and submodules included whatever the person's git
    /// settings say about hiding them. nil when git could not answer: that is "unknown", never "clean".
    public var isDirty: Bool? {
        git(["status", "--porcelain=v1", "-z", "--untracked-files=normal", "--ignore-submodules=none"]).map { !$0.isEmpty }
    }

    /// "clean", or a hash of the uncommitted changes: the pinned diff against HEAD, then every untracked
    /// file as name, NUL, size, NUL, bytes, all streamed through the hash (a large recording left in the
    /// clone is never held in memory). `scripts/tree-hash.sh` computes the same value for `app/build.sh`, so
    /// a copy built from this working tree and the working tree compare equal, an edit to a file not yet
    /// added to git included. nil when git failed or a file could not be read.
    public var fingerprint: String? {
        guard let dirty = isDirty else { return nil }
        guard dirty else { return "clean" }
        var hasher = SHA256()
        guard run(["-c", "core.quotepath=off", "diff", "HEAD", "--no-ext-diff", "--no-textconv", "--no-color",
                   "--no-renames", "--diff-algorithm=myers", "--no-indent-heuristic",
                   "--src-prefix=a/", "--dst-prefix=b/", "--unified=3"], sink: { hasher.update(data: $0) }),
              let listing = git(["ls-files", "-z", "--others", "--exclude-standard"]) else { return nil }
        for name in listing.split(separator: 0, omittingEmptySubsequences: true) {
            let url = root.appending(path: String(decoding: name, as: UTF8.self)).resolvingSymlinksInPath()
            hasher.update(data: Data(name) + [0])
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else {
                hasher.update(data: Data("0".utf8) + [0])          // a folder, a device, a broken link: size 0, no bytes
                continue
            }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            hasher.update(data: Data(String(values?.fileSize ?? 0).utf8) + [0])
            while case let chunk = (try? handle.read(upToCount: 1 << 20)) ?? Data(), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// How the commit a copy was built from relates to this clone's head; nil when git could not say.
    public func relation(toInstalled installed: String) -> CloneRelation? {
        guard let head else { return nil }
        guard git(["cat-file", "-e", "\(installed)^{commit}"]) != nil else { return .unrelated }
        if installed == head { return .same }
        if git(["merge-base", "--is-ancestor", installed, head]) != nil {
            return .cloneAhead(Int(text(["rev-list", "--count", "\(installed)..\(head)"]) ?? "") ?? 0)
        }
        if git(["merge-base", "--is-ancestor", head, installed]) != nil {
            return .installAhead(Int(text(["rev-list", "--count", "\(head)..\(installed)"]) ?? "") ?? 0)
        }
        return .unrelated
    }

    /// Everything This Copy needs, in one read; nil when any part of it could not be read.
    public func facts(installed: String?) -> CloneFacts? {
        guard let dirty = isDirty, let fingerprint else { return nil }
        let relation: CloneRelation
        if let installed { guard let found = self.relation(toInstalled: installed) else { return nil }; relation = found }
        else { relation = .unrelated }
        return CloneFacts(branch: branch, isDirty: dirty, fingerprint: fingerprint, relation: relation)
    }

    /// The clone's own changelog, uncommitted edits included: where This Copy's release notes come from.
    public var changelog: String? {
        try? String(contentsOf: root.appending(path: "CHANGELOG.md"), encoding: .utf8)
    }
}
