import Foundation

/// The identity a cleaner writes at the END of a `[TRASHED]` receipt:
/// `…  ->  /Users/x/.Trash/name  #id=16777234:12345` (device:inode of the item
/// in the Trash, which a rename keeps). It lets Undo prove the Trash still holds
/// THIS item and not a later one with the same name. Receipts written before it
/// have no suffix. Everything that reads a receipt's path goes through `split`,
/// so the suffix is never part of a path or a name.
public enum ReceiptIdentity {

    static let marker = "  #id="

    /// The text without the identity suffix, and the identity if there was one.
    public static func split(_ text: String) -> (text: String, id: String?) {
        guard let range = text.range(of: marker, options: .backwards) else { return (text, nil) }
        let id = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id.allSatisfy({ $0.isNumber || $0 == ":" }) else { return (text, nil) }
        return (String(text[..<range.lowerBound]), id)
    }

    /// `device:inode` of what is at `path` right now (the item itself, never what a
    /// symlink points to), or nil when nothing is there.
    public static func current(of path: String) -> String? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return "\(info.st_dev):\(info.st_ino)"
    }
}
