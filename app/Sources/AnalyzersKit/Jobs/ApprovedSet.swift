import Foundation

/// The rows a user left ticked in a review, ready to hand to the engine.
///
/// An apply acts on what a person reviewed and nothing else, so for every kind
/// whose review is a list of rows the list is ALWAYS written and sent — even
/// when nothing was unticked. Without it the engine would take whatever it
/// finds at apply time, including a file or a process that appeared after the
/// review. The engine re-derives its findings at apply time and intersects them
/// with this file, so a stale list can only ever shrink what gets touched.
public struct ApprovedSet: Sendable, Hashable {

    /// What the user left ticked, in review order: a pid for processes, a path
    /// for files.
    public private(set) var approved: [String]

    /// True when the review left at least one of its rows out. Information only:
    /// it does not decide whether a list is sent (a list is always sent).
    public private(set) var isNarrowed: Bool

    /// True for `ApprovedSet.everything`: no per-row list exists.
    public private(set) var isUnrestricted: Bool

    /// For a cleanup that can also quit apps: exactly the apps the review listed as "would quit".
    /// nil leaves the apply with the apps its preview was started with. An app that became eligible
    /// after the preview (it was not running, or its live session ended) is not in this list and is
    /// not quit.
    public let apps: [String]?

    /// For a list of processes: when each approved pid started, in epoch seconds, as the review saw it.
    /// The list is written as `<pid><TAB><start>`, and the engine approves the pid only while the process
    /// running under it started then: a pid the system has since given to another program is left alone.
    /// A key with no start here is written bare (the engine then trusts the pid alone, as before).
    public let starts: [String: Int]?

    /// `approvable` is every key the review offered; `deselected` the ones the
    /// user unticked.
    public init(approvable: [String], deselected: Set<String>) {
        self.approved = approvable.filter { !deselected.contains($0) && Self.isListable($0) }
        self.isNarrowed = !deselected.isEmpty
        self.isUnrestricted = false
        self.apps = nil
        self.starts = nil
    }

    /// A key the list can carry. The list is one key per line, so a key with a line
    /// break is two lines, and one of them could approve another item. Such a row
    /// is never written to the list; a review shows it as not choosable, with
    /// `unlistableReason`.
    ///
    /// Tested on BYTES. Swift treats a carriage return followed by a line feed as ONE character,
    /// so `contains("\n")` and `contains("\r")` are both false for a key that holds that pair,
    /// while the script reading the list still sees two lines.
    public static func isListable(_ key: String) -> Bool {
        !key.isEmpty && !key.utf8.contains { $0 == 0x0A || $0 == 0x0D || $0 == 0x00 }
    }

    public static let unlistableReason = "Its name contains a line break, so it can't be named safely to the cleaning tool and is left alone."

    private init() {
        approved = []
        isNarrowed = false
        isUnrestricted = true
        apps = nil
        starts = nil
    }

    private init(copying other: ApprovedSet, apps: [String]?, starts: [String: Int]?) {
        approved = other.approved
        isNarrowed = other.isNarrowed
        isUnrestricted = other.isUnrestricted
        self.apps = apps
        self.starts = starts
    }

    /// The same set, with exactly these apps to quit at apply time.
    public func withApps(_ apps: [String]) -> ApprovedSet { ApprovedSet(copying: self, apps: apps, starts: starts) }

    /// The same set, naming each approved process by when it started (key → epoch seconds).
    public func withStarts(_ starts: [String: Int]) -> ApprovedSet { ApprovedSet(copying: self, apps: apps, starts: starts) }

    /// A copy of THIS set restricted to the keys of `all` that are in `keep`: the one way a set is
    /// narrowed after a caller has produced it (the review's clamp, the frozen set a confirmation
    /// shows). It starts from a copy of itself, so any other field this type gains rides along;
    /// NEW FIELDS MUST BE COPIED HERE, never rebuilt by a caller through `init(approvable:deselected:)`.
    /// A key that cannot be listed is never kept, whatever the caller asked.
    public func restricted(over all: [String], keeping keep: Set<String>) -> ApprovedSet {
        var copy = self
        copy.approved = all.filter { keep.contains($0) && Self.isListable($0) }
        copy.isNarrowed = all.contains { !keep.contains($0) }
        copy.isUnrestricted = false
        return copy
    }

    /// For jobs with no per-row approval: Spotlight, Time Machine,
    /// unused apps and recordings, whose scripts take no list. Never valid for a
    /// kind that takes one (`JobKind.takesReviewedList`): `apply(from:)` refuses it.
    public static let everything = ApprovedSet()

    /// Writes the approved keys to a temp file and returns it, or nil when the
    /// kind takes no list. Always written for the kinds that do, even when empty
    /// (an empty list makes the engine touch nothing). The file format is one key
    /// per line, no trailing newline; a process is `<pid><TAB><start>` when its start is known.
    public func writeFile(for kind: JobKind, in directory: URL = FileManager.default.temporaryDirectory) throws -> URL? {
        guard kind.takesReviewedList else { return nil }
        let file = directory.appending(path: "mac-analyzers-approved-\(UUID().uuidString).txt")
        let lines = approved.map { key in starts?[key].map { "\(key)\t\($0)" } ?? key }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
