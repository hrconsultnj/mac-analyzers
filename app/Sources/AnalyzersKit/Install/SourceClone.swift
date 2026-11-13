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

    /// The flags every call starts with (see the type's comment). Keep in step with scripts/tree-hash.sh.
    static let safeArguments = ["--no-optional-locks", "--no-pager", "--attr-source=\(emptyTree)"]

    /// The configuration every call is given, through `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n`
    /// (key and value are separate there, so a driver whose name contains "=" can still be named; `-c`
    /// splits at the first "="). The command line outranks every file, `include.path` and `includeIf`.
    static let fixedSettings: [(key: String, value: String)] = [
        ("core.fsmonitor", "false"), ("core.useBuiltinFSMonitor", "false"), ("core.hooksPath", "/dev/null"),
        ("core.attributesFile", "/dev/null"), ("core.quotepath", "off"),
    ]

    /// The environment of every call: minimal, and with these settings. `GIT_NO_LAZY_FETCH` keeps a partial
    /// clone from running its promisor remote's program to fetch a missing object: git fails instead, and a
    /// failure reads "unknown".
    static func environment(settings: [(key: String, value: String)]) -> [String: String] {
        var environment: [String: String] = [
            "PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LC_ALL": "C",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_ATTR_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0", "GIT_NO_LAZY_FETCH": "1",
            "GIT_CONFIG_COUNT": String(settings.count),
        ]
        for (index, setting) in settings.enumerated() {
            environment["GIT_CONFIG_KEY_\(index)"] = setting.key
            environment["GIT_CONFIG_VALUE_\(index)"] = setting.value
        }
        return environment
    }

    /// What one read of the clone is allowed to do, decided once per read: the fixed settings plus every filter
    /// and diff driver the clone defines, emptied. nil when the clone cannot be read safely: its
    /// `info/attributes` (the one place left that can pick a driver) is not empty, or git cannot say.
    private struct Session {
        var settings: [(key: String, value: String)]
    }

    private func session() -> Session? {
        let fixed = Self.fixedSettings
        // the only attribute source left once --attr-source, core.attributesFile and GIT_ATTR_NOSYSTEM are set
        var path = Data()
        guard run(["rev-parse", "--git-path", "info/attributes"], settings: fixed, sink: { path.append($0) }) else { return nil }
        let relative = String(decoding: path, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let attributes = URL(fileURLWithPath: relative, relativeTo: root)
        if let size = (try? FileManager.default.attributesOfItem(atPath: attributes.path))?[.size] as? Int, size > 0 { return nil }
        // belt and braces: every driver the clone's configuration defines is emptied too
        var names = Data()
        let listed = run(["config", "--name-only", "--get-regexp", #"^(filter|diff)\..*\.(clean|smudge|process|textconv|command|required)$"#],
                         settings: fixed, sink: { names.append($0) })
        guard listed || names.isEmpty else { return nil }
        let drivers = String(decoding: names, as: UTF8.self).split(separator: "\n").map { key -> (key: String, value: String) in
            (String(key), key.hasSuffix(".required") ? "false" : "")
        }
        return Session(settings: fixed + drivers)
    }

    /// Runs `git` on the clone, handing what it prints to `sink` as it comes; false when it fails.
    @discardableResult
    private func run(_ arguments: [String], settings: [(key: String, value: String)], sink: (Data) -> Void) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = Self.safeArguments + ["-C", root.path] + arguments
        process.environment = Self.environment(settings: settings)
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
    private func git(_ arguments: [String], settings: [(key: String, value: String)]? = nil) -> Data? {
        var data = Data()
        return run(arguments, settings: settings ?? Self.fixedSettings) { data.append($0) } ? data : nil
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

    /// Whether anything is uncommitted, untracked files included whatever the person's git settings say about
    /// hiding them. Submodules are asked about with `--ignore-submodules=dirty`: git then never runs inside
    /// one (its own configuration and attributes are not ours to trust). nil when git could not answer or the
    /// clone cannot be read safely: that is "unknown", never "clean".
    public var isDirty: Bool? { session().flatMap(isDirty(in:)) }

    private func isDirty(in session: Session) -> Bool? {
        git(["status", "--porcelain=v1", "-z", "--untracked-files=normal", "--ignore-submodules=dirty"],
            settings: session.settings).map { !$0.isEmpty }
    }

    /// "clean", or a hash of the uncommitted changes: the pinned diff against HEAD, then every untracked
    /// file as name, NUL, size, NUL, bytes, all streamed through the hash (a large recording left in the
    /// clone is never held in memory). `scripts/tree-hash.sh` computes the same value for `app/build.sh`, so
    /// a copy built from this working tree and the working tree compare equal, an edit to a file not yet
    /// added to git included. nil when git failed (a missing object in a partial clone included), a file
    /// could not be read, or the clone has a submodule while it has uncommitted changes: "unknown".
    public var fingerprint: String? { session().flatMap { fingerprint(in: $0) } }

    private func fingerprint(in session: Session, dirty known: Bool? = nil) -> String? {
        guard let dirty = known ?? isDirty(in: session) else { return nil }
        guard dirty else { return "clean" }
        // a gitlink: what is inside a submodule cannot be hashed without running git there
        guard let staged = git(["ls-files", "--stage", "-z"], settings: session.settings),
              !staged.split(separator: 0, omittingEmptySubsequences: true).contains(where: { $0.starts(with: Array("160000 ".utf8)) })
        else { return nil }
        var hasher = SHA256()
        guard run(["diff", "HEAD", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames",
                   "--ignore-submodules=dirty", "--diff-algorithm=myers", "--no-indent-heuristic",
                   "--src-prefix=a/", "--dst-prefix=b/", "--unified=3"], settings: session.settings,
                  sink: { hasher.update(data: $0) }),
              let listing = git(["ls-files", "-z", "--others", "--exclude-standard"], settings: session.settings) else { return nil }
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
            // each chunk is drained from the autorelease pool at once: without it a synchronous loop keeps
            // every chunk alive and a 400 MB file peaks at 850 MB
            var reading = true
            while reading {
                autoreleasepool {
                    let chunk = (try? handle.read(upToCount: 1 << 20)) ?? Data()
                    if chunk.isEmpty { reading = false } else { hasher.update(data: chunk) }
                }
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

    /// Everything This Copy needs, in one read (one look at the configuration, not one per command); nil when
    /// any part of it could not be read.
    public func facts(installed: String?) -> CloneFacts? {
        guard let session = session(), let dirty = isDirty(in: session), let fingerprint = fingerprint(in: session, dirty: dirty) else { return nil }
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
