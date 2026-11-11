import Foundation

/// The rows a user left ticked in a review, ready to hand to the engine.
///
/// The engine re-derives its findings at apply time and intersects them with
/// this file, so a stale list can only ever shrink what gets touched.
public struct ApprovedSet: Sendable, Hashable {

    /// What the user left ticked, in review order: a pid for processes, a path
    /// for files.
    public private(set) var approved: [String]

    /// True when the user deselected at least one row.
    public private(set) var isNarrowed: Bool

    /// True for `ApprovedSet.everything`: no per-row list exists.
    public private(set) var isUnrestricted: Bool

    /// `approvable` is every key the review offered; `deselected` the ones the
    /// user unticked.
    public init(approvable: [String], deselected: Set<String>) {
        self.approved = approvable.filter { !deselected.contains($0) }
        self.isNarrowed = !deselected.isEmpty
        self.isUnrestricted = false
    }

    private init() {
        approved = []
        isNarrowed = false
        isUnrestricted = true
    }

    /// A copy of THIS set restricted to the keys of `all` that are in `keep`: the one way a set is
    /// narrowed after a caller has produced it (the review's clamp, the frozen set a confirmation
    /// shows). It starts from a copy of itself, so any other field this type gains rides along;
    /// NEW FIELDS MUST BE COPIED HERE, never rebuilt by a caller through `init(approvable:deselected:)`.
    public func restricted(over all: [String], keeping keep: Set<String>) -> ApprovedSet {
        var copy = self
        copy.approved = all.filter { keep.contains($0) }
        copy.isNarrowed = all.contains { !keep.contains($0) }
        copy.isUnrestricted = false
        return copy
    }

    /// For jobs with no per-row approval (Spotlight, login items, Time Machine)
    /// and for cleaners where nothing was deselected. Never valid for a kind
    /// that must send its list (`JobKind.alwaysSendsApprovalList`).
    public static let everything = ApprovedSet()

    /// Writes the approved keys to a temp file and returns it, or nil when the
    /// kind needs no flag.
    ///
    /// Nothing deselected means no flag at all, so the common case runs
    /// exactly the command it always did. Temp clean always sends its list:
    /// temp folders change by the minute, and an item that crosses the age line
    /// between preview and apply must not ride along unreviewed.
    ///
    /// The file format is one key per line, no trailing newline.
    public func writeFile(for kind: JobKind, in directory: URL = FileManager.default.temporaryDirectory) throws -> URL? {
        guard kind.approvalFlag != nil else { return nil }
        guard isNarrowed || kind.alwaysSendsApprovalList else { return nil }
        let file = directory.appending(path: "mac-analyzers-approved-\(UUID().uuidString).txt")
        try approved.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
