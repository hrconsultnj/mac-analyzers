import CryptoKit
import Foundation

/// The git clone an installed copy was built from, read with plain local `git` commands. Nothing here
/// fetches, pulls or writes: a channel that needs the network asks GitHub's public API instead, and an
/// install is `upgrade.command`'s job, started by the person.
public struct SourceClone: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// The clone this app belongs to: the suite root, when it is a git working tree. A downloaded app's
    /// root is inside its bundle and is not one.
    public static var current: SourceClone? {
        let clone = SourceClone(root: AnalyzersPaths.suiteRoot)
        return clone.isWorkingTree ? clone : nil
    }

    /// Runs `git` on the clone; nil when it fails.
    private func git(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // --no-optional-locks: reading status must never write to the person's repository
        process.arguments = ["--no-optional-locks", "-C", root.path] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private func text(_ arguments: [String]) -> String? {
        git(arguments).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public var isWorkingTree: Bool { text(["rev-parse", "--is-inside-work-tree"]) == "true" }

    /// The branch, nil on a detached head.
    public var branch: String? {
        guard let name = text(["rev-parse", "--abbrev-ref", "HEAD"]), name != "HEAD" else { return nil }
        return name
    }

    public var head: String? { text(["rev-parse", "HEAD"]) }

    public var isDirty: Bool { !(text(["status", "--porcelain"]) ?? "").isEmpty }

    /// "clean", or a hash of the uncommitted changes: the diff against HEAD, then every untracked file as
    /// name, NUL, size, NUL, bytes (git lists them in a stable order). `scripts/tree-hash.sh` computes the
    /// same value for `app/build.sh`, so a copy built from this working tree and the working tree compare
    /// equal — an edit to a file not yet added to git included. The diff is pinned (no external diff, no
    /// text filter, no colour, one algorithm, fixed prefixes, unquoted paths) so no git setting of the
    /// person's changes its bytes.
    public var fingerprint: String {
        guard isDirty else { return "clean" }
        var bytes = git(["-c", "core.quotepath=off", "diff", "HEAD", "--no-ext-diff", "--no-textconv", "--no-color",
                         "--no-renames", "--diff-algorithm=myers", "--no-indent-heuristic",
                         "--src-prefix=a/", "--dst-prefix=b/", "--unified=3"]) ?? Data()
        let listing = git(["ls-files", "-z", "--others", "--exclude-standard"]) ?? Data()
        for name in listing.split(separator: 0, omittingEmptySubsequences: true) {
            let path = String(decoding: name, as: UTF8.self)
            let content = (try? Data(contentsOf: root.appending(path: path))) ?? Data()
            bytes.append(Data(name))
            bytes.append(0)
            bytes.append(Data(String(content.count).utf8))
            bytes.append(0)
            bytes.append(content)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// How the commit a copy was built from relates to this clone's head.
    public func relation(toInstalled installed: String) -> CloneRelation {
        guard git(["cat-file", "-e", "\(installed)^{commit}"]) != nil, let head else { return .unrelated }
        if installed == head { return .same }
        if git(["merge-base", "--is-ancestor", installed, head]) != nil {
            return .cloneAhead(Int(text(["rev-list", "--count", "\(installed)..\(head)"]) ?? "") ?? 0)
        }
        if git(["merge-base", "--is-ancestor", head, installed]) != nil {
            return .installAhead(Int(text(["rev-list", "--count", "\(head)..\(installed)"]) ?? "") ?? 0)
        }
        return .unrelated
    }

    /// Everything the channels need, in one read.
    public func facts(installed: String?) -> CloneFacts {
        CloneFacts(branch: branch, isDirty: isDirty, fingerprint: fingerprint,
                   relation: installed.map(relation(toInstalled:)) ?? .unrelated)
    }

    /// The clone's own changelog, uncommitted edits included: where This Copy's release notes come from.
    public var changelog: String? {
        try? String(contentsOf: root.appending(path: "CHANGELOG.md"), encoding: .utf8)
    }
}
