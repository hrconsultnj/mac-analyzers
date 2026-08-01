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
    }

    public let originalPath: String
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
        var trashed: [(path: String, size: String)] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[RESTORED]") {
                if let path = pathPart(of: trimmed, prefix: "[RESTORED]") {
                    restored.insert(path)
                }
            } else if trimmed.hasPrefix("[TRASHED]") {
                if let path = pathPart(of: trimmed, prefix: "[TRASHED]"),
                   let size = sizePart(of: trimmed, prefix: "[TRASHED]") {
                    trashed.append((path, size))
                }
            }
        }
        let fm = FileManager.default
        return trashed.reversed()
            .filter { !restored.contains($0.path) }
            .map { entry in
                let basename = (entry.path as NSString).lastPathComponent
                let inTrash = fm.fileExists(atPath: trashDir.appending(path: basename).path)
                let occupied = fm.fileExists(atPath: entry.path)
                let state: TrashedItem.Restorability =
                    !inTrash ? .trashCopyGone : occupied ? .pathOccupied : .restorable
                return TrashedItem(originalPath: entry.path, sizeText: entry.size,
                                   restorability: state)
            }
    }

    public enum RestoreError: Error { case notRestorable }

    /// Move the Trash copy back to its original path, receipt included.
    public static func restore(_ item: TrashedItem) throws {
        guard item.restorability == .restorable else { throw RestoreError.notRestorable }
        let from = trashDir.appending(path: item.basename)
        try FileManager.default.moveItem(
            at: from, to: URL(fileURLWithPath: item.originalPath))
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
