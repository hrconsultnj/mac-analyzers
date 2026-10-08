import Foundation

/// The un-kill side of a kill-guard: janitor moves things to the Trash and
/// writes receipts — this reads those receipts and can move an item back,
/// with its own [RESTORED] receipt. App-side by design: restoring from the
/// user's Trash is user territory, but every restore is still logged.
public struct TrashedItem: Identifiable, Sendable {
    public enum Restorability: Sendable, Equatable {
        case restorable
        case trashCopyGone
        case pathOccupied
        /// Receipt predates destination recording — restoring would mean
        /// guessing which Trash file this was, so we refuse.
        case destinationUnknown
    }

    public let originalPath: String
    /// The receipt log this came from — a restore writes its own receipt
    /// back to the same log, so each cleaner's history stays whole.
    public let ledger: URL
    /// Which cleaner moved it ("Janitor" / "Temp & Agents"), for the Undo list.
    public let source: String
    /// Where the janitor actually put it. Recorded in the receipt — never
    /// guessed from the basename, because a name collision means the Trash
    /// copy was renamed and the guess would point at a DIFFERENT file the
    /// user trashed themselves.
    public let trashPath: String?
    public let sizeText: String
    public let restorability: Restorability

    public var id: String { ledger.lastPathComponent + "|" + originalPath }
    /// A family token ("<dir>/<family>*") stands for many siblings that went
    /// into ONE Trash folder; restoring moves that folder's children back.
    public var isGroup: Bool { originalPath.hasSuffix("*") }
    public var basename: String {
        let last = (originalPath as NSString).lastPathComponent
        return isGroup ? String(last.dropLast()) + "…" : last
    }
}

public enum UndoLedger {

    public static var trashDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
    }

    /// Every receipt log that records Trash moves, and the name shown for it.
    public static let ledgers: [(url: URL, source: String)] = [
        (AnalyzersPaths.janitorLog, "Janitor"),
        (AnalyzersPaths.tempCleanLog, "Temp & Agents"),
    ]

    /// TRASHED receipts from every ledger, newest first within each, excluding
    /// ones that already carry a RESTORED receipt.
    public static func trashedItems() -> [TrashedItem] {
        ledgers.flatMap { trashedItems(in: $0.url, source: $0.source) }
    }

    static func trashedItems(in ledger: URL, source: String) -> [TrashedItem] {
        guard let text = try? String(contentsOf: ledger, encoding: .utf8)
        else { return [] }
        var restored: Set<String> = []
        var trashed: [(path: String, dest: String?, size: String)] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[RESTORED]") {
                if let path = pathPart(of: trimmed, prefix: "[RESTORED]") {
                    restored.insert(path)
                }
            } else if trimmed.hasPrefix("[TRASHED]") {
                if let path = pathPart(of: trimmed, prefix: "[TRASHED]"),
                   let size = sizePart(of: trimmed, prefix: "[TRASHED]") {
                    // "…  <original>  ->  <trash destination>" (newer receipts)
                    let parts = path.components(separatedBy: "  ->  ")
                    trashed.append((parts[0].trimmingCharacters(in: .whitespaces),
                                    parts.count > 1
                                        ? parts[1].trimmingCharacters(in: .whitespaces)
                                        : nil,
                                    size))
                }
            }
        }
        let fm = FileManager.default
        return trashed.reversed()
            .filter { !restored.contains($0.path) }
            .map { entry in
                let state: TrashedItem.Restorability
                if let dest = entry.dest {
                    state = !fm.fileExists(atPath: dest) ? .trashCopyGone
                          : occupied(original: entry.path, trashCopy: dest) ? .pathOccupied
                          : .restorable
                } else {
                    state = .destinationUnknown
                }
                return TrashedItem(originalPath: entry.path, ledger: ledger, source: source,
                                   trashPath: entry.dest,
                                   sizeText: entry.size, restorability: state)
            }
    }

    public enum RestoreError: Error { case notRestorable }

    /// A single item is blocked when something now sits at its old path; a
    /// family is blocked when ANY of its members' old paths is taken — a
    /// partial restore would leave the receipt claiming more than it did.
    private static func occupied(original: String, trashCopy: String) -> Bool {
        let fm = FileManager.default
        guard original.hasSuffix("*") else { return fm.fileExists(atPath: original) }
        let parent = (original as NSString).deletingLastPathComponent
        let members = (try? fm.contentsOfDirectory(atPath: trashCopy)) ?? []
        return members.contains { fm.fileExists(atPath: (parent as NSString).appendingPathComponent($0)) }
    }

    /// Move the Trash copy back to its original path, receipt included. A
    /// family token moves each member of its Trash folder back into the
    /// folder they came from, then removes the emptied Trash folder.
    public static func restore(_ item: TrashedItem) throws {
        guard item.restorability == .restorable,
              let trashPath = item.trashPath        // never guessed
        else { throw RestoreError.notRestorable }
        let fm = FileManager.default
        if item.isGroup {
            let parent = (item.originalPath as NSString).deletingLastPathComponent
            for member in try fm.contentsOfDirectory(atPath: trashPath) {
                try fm.moveItem(atPath: (trashPath as NSString).appendingPathComponent(member),
                                toPath: (parent as NSString).appendingPathComponent(member))
            }
            try? fm.removeItem(atPath: trashPath)   // now empty
        } else {
            try fm.moveItem(at: URL(fileURLWithPath: trashPath),
                            to: URL(fileURLWithPath: item.originalPath))
        }
        appendReceipt("[RESTORED] \(item.sizeText)  \(item.originalPath)", to: item.ledger)
    }

    private static func appendReceipt(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    // "[TAG] 1.5 MB  /path with spaces" — size is the two tokens after the
    // tag; the path is everything after the double space.
    private static func pathPart(of line: String, prefix: String) -> String? {
        guard let range = line.range(of: "  ") else { return nil }
        let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") ? path : nil
    }

    private static func sizePart(of line: String, prefix: String) -> String? {
        let rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let range = rest.range(of: "  ") else { return nil }
        return String(rest[rest.startIndex..<range.lowerBound])
    }
}
