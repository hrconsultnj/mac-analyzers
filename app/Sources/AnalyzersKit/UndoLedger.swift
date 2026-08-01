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
    /// Where the janitor actually put it. Recorded in the receipt — never
    /// guessed from the basename, because a name collision means the Trash
    /// copy was renamed and the guess would point at a DIFFERENT file the
    /// user trashed themselves.
    public let trashPath: String?
    public let sizeText: String
    public let restorability: Restorability

    public var id: String { originalPath }
    public var basename: String { (originalPath as NSString).lastPathComponent }
}

public enum UndoLedger {

    public static var trashDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
    }

    /// TRASHED receipts from the janitor log, newest first, excluding ones
    /// that already carry a RESTORED receipt.
    public static func trashedItems() -> [TrashedItem] {
        guard let text = try? String(contentsOf: AnalyzersPaths.janitorLog, encoding: .utf8)
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
                          : fm.fileExists(atPath: entry.path) ? .pathOccupied
                          : .restorable
                } else {
                    state = .destinationUnknown
                }
                return TrashedItem(originalPath: entry.path, trashPath: entry.dest,
                                   sizeText: entry.size, restorability: state)
            }
    }

    public enum RestoreError: Error { case notRestorable }

    /// Move the Trash copy back to its original path, receipt included.
    public static func restore(_ item: TrashedItem) throws {
        guard item.restorability == .restorable,
              let trashPath = item.trashPath        // never guessed
        else { throw RestoreError.notRestorable }
        try FileManager.default.moveItem(
            at: URL(fileURLWithPath: trashPath),
            to: URL(fileURLWithPath: item.originalPath))
        appendReceipt("[RESTORED] \(item.sizeText)  \(item.originalPath)")
    }

    private static func appendReceipt(_ line: String) {
        let url = AnalyzersPaths.janitorLog
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
