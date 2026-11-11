import Foundation

/// The plain word a person reads for each status token the engine prints in
/// capitals (`DRY`, `KILLED`, `NEEDS SUDO`). The token stays the identifier — the
/// parsers match it and the logs contain it — and `plainLabel` is the only place
/// it is turned into words: one answer per token, per kind of thing, so `DRY`
/// reads "Would Close" for a process and "Would Remove" for a folder, and no
/// screen shows the token itself. Every switch is exhaustive: a token added to a
/// parser does not compile until it has its word here. Labels are names (title
/// style) and are checked by `agent-runner --probe-names`.
///
/// Reached from screens through `UIComponents.TokenLabel.plain(_:)`.
extension SpotlightExposureItem.Status {
    public var plainLabel: String {
        switch self {
        case .dry: "Would Fence Off"
        case .fenced: "Fenced Off"
        }
    }
}

extension SpotlightAuditRun.Verdict {
    public var plainLabel: String {
        switch self {
        case .progressing: "Indexing"
        case .idleOrComplete: "Up to Date"
        case .notRunning: "Not Indexing"
        case .unknown: "Unknown"
        }
    }
}

extension TempItem.Status {
    public var plainLabel: String {
        switch self {
        case .dry: "Would Clear"
        case .trashed: "Moved to Trash"
        case .deleted: "Deleted"
        case .failed: "Couldn't Clear"
        case .skip: "Skipped"
        case .recent: "Too Recent"
        case .inUse: "In Use"
        case .protected: "Protected"
        case .notYours: "Not Yours"
        case .keep: "Kept"
        case .system: "System"
        case .history: "History"
        case .kept: "Kept"
        case .managed: "Managed by an App"
        }
    }
}

extension TempMount.Status {
    public var plainLabel: String {
        switch self {
        case .mounted: "Mounted"
        case .ejected: "Ejected"
        case .ejectFailed: "Couldn't Eject"
        }
    }
}

extension LoginItemEntry.Verdict {
    public var plainLabel: String {
        switch self {
        case .orphan: "Leftover"
        case .orphanSudo: "Needs Administrator"
        case .removed: "Removed"
        case .leftover: "Might Be a Leftover"
        case .skip: "Skipped"
        }
    }
}

extension ReapItem.Status {
    public var plainLabel: String {
        switch self {
        case .dry: "Would Close"
        case .killed: "Closed"
        case .reported: "Reported"
        case .gone: "Already Gone"
        case .exempt: "Protected"
        case .quit: "Quit"
        case .skip: "Skipped"
        }
    }
}

extension StoragePathItem.Status {
    public var plainLabel: String {
        switch self {
        case .dry: "Would Remove"
        case .deleted: "Deleted"
        case .trashed: "Moved to Trash"
        case .restored: "Put Back"
        case .failed: "Couldn't Remove"
        }
    }
}

/// Words for tokens that appear in a line of text rather than as a typed value
/// (`DRY RUN`, `DONE`), and every typed token with its word, for the check.
public enum TokenWords {

    /// A raw token in capitals read from a line; nil when it has no plain word
    /// of its own (the caller then title-cases it).
    public static func plain(_ token: String) -> String? {
        switch token.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).uppercased() {
        case "DRY RUN", "DRY": "Preview"
        case "DONE": "Done"
        case "KILLED": "Closed"
        case "FAILED": "Failed"
        case "SKIP", "SKIPPED": "Skipped"
        case "NEEDS SUDO": "Needs Administrator"
        case "IDLE OR COMPLETE": "Up to Date"
        default: nil
        }
    }

    /// Every typed token and its word, for `agent-runner --probe-names`.
    public static var all: [(token: String, label: String)] {
        var rows: [(String, String)] = []
        rows += [SpotlightExposureItem.Status.dry, .fenced].map { ($0.rawValue, $0.plainLabel) }
        rows += [SpotlightAuditRun.Verdict.progressing, .idleOrComplete, .notRunning, .unknown]
            .map { ($0.rawValue, $0.plainLabel) }
        rows += TempItem.Status.allCases.map { ($0.rawValue, $0.plainLabel) }
        rows += [TempMount.Status.mounted, .ejected, .ejectFailed].map { ($0.rawValue, $0.plainLabel) }
        rows += [LoginItemEntry.Verdict.orphan, .orphanSudo, .removed, .leftover, .skip]
            .map { ($0.rawValue, $0.plainLabel) }
        rows += [ReapItem.Status.dry, .killed, .reported, .gone, .exempt, .quit, .skip]
            .map { ($0.rawValue, $0.plainLabel) }
        rows += [StoragePathItem.Status.dry, .deleted, .trashed, .restored, .failed]
            .map { ($0.rawValue, $0.plainLabel) }
        return rows.map { (token: $0.0, label: $0.1) }
    }
}
