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
    public let approved: [String]

    /// True for `ApprovedSet.everything`: no per-row list exists.
    public let isUnrestricted: Bool

    /// `approvable` is every key the review offered; `deselected` the ones the
    /// user unticked.
    public init(approvable: [String], deselected: Set<String>) {
        self.approved = approvable.filter { !deselected.contains($0) && Self.isListable($0) }
        self.isUnrestricted = false
    }

    /// A key the list can carry. The list is one key per line, so a key with a line
    /// break is two lines, and one of them could approve another item. Such a row
    /// is never written to the list; a review shows it as not choosable, with
    /// `unlistableReason`.
    public static func isListable(_ key: String) -> Bool {
        !key.isEmpty && !key.contains("\n") && !key.contains("\r")
    }

    public static let unlistableReason = "Its name contains a line break, so it can't be named safely to the cleaning tool and is left alone."

    private init() {
        approved = []
        isUnrestricted = true
    }

    /// For jobs with no per-row approval: Spotlight, login items, Time Machine,
    /// unused apps and recordings, whose scripts take no list. Never valid for a
    /// kind that takes one (`JobKind.takesReviewedList`): `apply(from:)` refuses it.
    public static let everything = ApprovedSet()

    /// Writes the approved keys to a temp file and returns it, or nil when the
    /// kind takes no list. Always written for the kinds that do, even when empty
    /// (an empty list makes the engine touch nothing). The file format is one key
    /// per line, no trailing newline.
    public func writeFile(for kind: JobKind, in directory: URL = FileManager.default.temporaryDirectory) throws -> URL? {
        guard kind.takesReviewedList else { return nil }
        let file = directory.appending(path: "mac-analyzers-approved-\(UUID().uuidString).txt")
        try approved.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
