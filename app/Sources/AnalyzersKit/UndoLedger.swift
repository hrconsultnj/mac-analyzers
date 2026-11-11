import Foundation

/// The un-kill side of a kill-guard: the cleaners move things to the Trash and
/// write receipts — this reads those receipts and can move an item back, with
/// its own `[RESTORED]` receipt. App-side by design: restoring from the user's
/// Trash is user territory, but every restore is still logged.
///
/// A restore moves a real file, so it moves only what it can PROVE is the thing
/// the cleaner trashed: the Trash path must resolve inside `~/.Trash`, the item
/// there must carry the identity (device:inode) the receipt recorded — or, for
/// a receipt written before identities existed, must have entered the Trash
/// when the run happened — and every destination is checked again at the
/// moment of the click, not only when the list was built.
public struct TrashedItem: Identifiable, Sendable {
    public enum Restorability: Sendable, Equatable {
        case restorable
        case trashCopyGone
        case pathOccupied
        /// Receipt predates destination recording — restoring would mean
        /// guessing which Trash file this was, so we refuse.
        case destinationUnknown
        /// What is at the Trash path now is not what the cleaner put there (a later
        /// item with the same name, or a file swapped in).
        case notTheSameItem
        /// An old receipt (no identity) and the Trash item did not arrive when the run did.
        case cannotVerify
        /// The folder it came from is gone.
        case parentGone
        /// A folder on the way to the original place has been replaced by a link, so the
        /// item would land somewhere other than the place the receipt names.
        case parentRedirected
        /// The receipt names a place that is not inside the Trash, or a path with `..`.
        case unsafePath
    }

    public let originalPath: String
    /// The receipt log this came from — a restore writes its own receipt
    /// back to the same log, so each cleaner's history stays whole.
    public let ledger: URL
    /// Which cleaner moved it ("Janitor" / "Temp & Agents"), for the Undo list.
    public let source: String
    /// Where the cleaner actually put it. Recorded in the receipt — never
    /// guessed from the basename, because a name collision means the Trash
    /// copy was renamed and the guess would point at a DIFFERENT file the
    /// user trashed themselves.
    public let trashPath: String?
    public let sizeText: String
    public let restorability: Restorability
    /// `device:inode` the cleaner recorded for the Trash item; nil on older receipts.
    public let identity: String?
    /// When the run that wrote the receipt started.
    public let receiptDate: Date?

    @_spi(TestSupport) public init(originalPath: String, ledger: URL, source: String, trashPath: String?,
                                   sizeText: String, restorability: Restorability, identity: String?,
                                   receiptDate: Date?) {
        self.originalPath = originalPath
        self.ledger = ledger
        self.source = source
        self.trashPath = trashPath
        self.sizeText = sizeText
        self.restorability = restorability
        self.identity = identity
        self.receiptDate = receiptDate
    }

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

    /// How close to a run's start an item without a recorded identity must have
    /// entered the Trash for a restore to trust it.
    static let legacyWindow: (before: TimeInterval, after: TimeInterval) = (60, 15 * 60)

    /// Every receipt log that records Trash moves, and the name shown for it.
    public static var ledgers: [(url: URL, source: String)] {
        [(AnalyzersPaths.janitorLog, "Janitor"),
         (AnalyzersPaths.tempCleanLog, "Temp & Agents")]
    }

    /// TRASHED receipts from every ledger, newest first within each, excluding
    /// ones that already carry a RESTORED receipt.
    public static func trashedItems() -> [TrashedItem] {
        ledgers.flatMap { trashedItems(in: $0.url, source: $0.source) }
    }

    @_spi(TestSupport) public static func trashedItems(in ledger: URL, source: String,
                                                       trash: URL = UndoLedger.trashDir) -> [TrashedItem] {
        guard let text = try? String(contentsOf: ledger, encoding: .utf8) else { return [] }
        struct Receipt { let path: String; let dest: String?; let size: String; let id: String?; let date: Date? }
        var trashed: [Receipt] = []
        var runDate: Date?
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[RESTORED]") {
                // a RESTORED line answers the latest TRASHED line for that path before it,
                // and no other (the same path can be trashed again later)
                if let path = pathPart(of: trimmed),
                   let index = trashed.lastIndex(where: { $0.path == path }) {
                    trashed.remove(at: index)
                }
            } else if trimmed.hasPrefix("[TRASHED]") {
                if let rest = pathPart(of: trimmed), let size = sizePart(of: trimmed, prefix: "[TRASHED]") {
                    // "…  <original>  ->  <trash destination>  #id=<dev:ino>" (newer receipts)
                    let (withoutID, id) = ReceiptIdentity.split(rest)
                    let parts = withoutID.components(separatedBy: "  ->  ")
                    trashed.append(Receipt(path: parts[0].trimmingCharacters(in: .whitespaces),
                                           dest: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil,
                                           size: size, id: id, date: runDate))
                }
            } else if trimmed.contains("|"), let date = TrendTotals.runDate(trimmed) {
                runDate = date      // a run's banner: the receipts below it were written then
            }
        }
        return trashed.reversed().map { entry in
            TrashedItem(originalPath: entry.path, ledger: ledger, source: source, trashPath: entry.dest,
                        sizeText: entry.size,
                        restorability: evaluate(original: entry.path, trashPath: entry.dest, identity: entry.id,
                                                receiptDate: entry.date, trash: trash),
                        identity: entry.id, receiptDate: entry.date)
        }
    }

    // MARK: - what a restore may do

    /// Whether `original` can be put back from `trashPath` right now. Used when
    /// the list is built AND again when Restore is clicked.
    static func evaluate(original: String, trashPath: String?, identity: String?, receiptDate: Date?,
                         trash: URL = UndoLedger.trashDir) -> TrashedItem.Restorability {
        let fm = FileManager.default
        guard original.hasPrefix("/"), !hasDotDot(original) else { return .unsafePath }
        guard let trashPath else { return .destinationUnknown }
        guard isInside(trashPath, trash: trash) else { return .unsafePath }
        guard (try? fm.attributesOfItem(atPath: trashPath)) != nil else { return .trashCopyGone }

        // is it the thing the cleaner put there?
        if let identity {
            guard ReceiptIdentity.current(of: trashPath) == identity else { return .notTheSameItem }
        } else {
            // an old receipt vouches for nothing but timing, so a link in the slot is not trusted
            guard (try? fm.attributesOfItem(atPath: trashPath))?[.type] as? FileAttributeType != .typeSymbolicLink,
                  let receiptDate,
                  let added = (try? URL(fileURLWithPath: trashPath)
                    .resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate,
                  added >= receiptDate.addingTimeInterval(-legacyWindow.before),
                  added <= receiptDate.addingTimeInterval(legacyWindow.after)
            else { return .cannotVerify }
        }

        let parent = (original as NSString).deletingLastPathComponent
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else { return .parentGone }
        guard resolvesToItself(parent) else { return .parentRedirected }
        return occupied(original: original, trashCopy: trashPath) ? .pathOccupied : .restorable
    }

    /// The folder is what the receipt named: following every link on the way lands on the same
    /// path (the system's own `/tmp` and `/var` links aside). A folder replaced by a link would
    /// send the restored item wherever the link points.
    static func resolvesToItself(_ folder: String) -> Bool {
        var walked = ""
        for part in folder.split(separator: "/") {
            walked += "/" + part
            guard !["/tmp", "/var", "/etc"].contains(walked) else { continue }    // the system's own links
            var info = stat()
            if lstat(walked, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK { return false }
        }
        return true
    }

    /// `..` anywhere in a path: refused, whatever it would resolve to.
    private static func hasDotDot(_ path: String) -> Bool {
        path.split(separator: "/").contains("..")
    }

    /// The Trash path must resolve, after symlinks, to a place directly inside the Trash.
    static func isInside(_ path: String, trash: URL) -> Bool {
        guard path.hasPrefix("/"), !hasDotDot(path) else { return false }
        let root = trash.resolvingSymlinksInPath().path
        // resolve the PARENT (an item that is itself a symlink is moved as a symlink)
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path
        let name = (path as NSString).lastPathComponent
        return parent == root && !name.isEmpty && name != "." && name != ".."
    }

    public enum RestoreError: Error, LocalizedError, Equatable {
        case notRestorable(TrashedItem.Restorability)
        case moveFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notRestorable(let why): "It can no longer be restored: \(UndoLedger.reason(why))"
            case .moveFailed(let detail): "The move failed: \(detail)"
            }
        }
    }

    /// The reason, in words, a restore is refused.
    public static func reason(_ state: TrashedItem.Restorability) -> String {
        switch state {
        case .restorable: "it can be restored."
        case .trashCopyGone: "the Trash has been emptied."
        case .pathOccupied: "something new is at the original location."
        case .destinationUnknown: "it was moved before the app recorded where it went."
        case .notTheSameItem: "the item in the Trash is not the one the cleanup moved there."
        case .cannotVerify: "the app cannot confirm the item in the Trash is the one the cleanup moved."
        case .parentGone: "the folder it came from no longer exists."
        case .parentRedirected: "a folder on the way has been replaced by a link, so it would land somewhere else."
        case .unsafePath: "the receipt names a location the app will not move files to or from."
        }
    }

    /// A single item is blocked when something now sits at its old path; a
    /// family is blocked when ANY of its members' old paths is taken — a
    /// partial restore would leave the receipt claiming more than it did.
    private static func occupied(original: String, trashCopy: String) -> Bool {
        let fm = FileManager.default
        guard original.hasSuffix("*") else { return (try? fm.attributesOfItem(atPath: original)) != nil }
        let parent = (original as NSString).deletingLastPathComponent
        let members = (try? fm.contentsOfDirectory(atPath: trashCopy)) ?? []
        return members.contains { (try? fm.attributesOfItem(atPath: (parent as NSString).appendingPathComponent($0))) != nil }
    }

    /// The tag of a family member's own receipt line. It is not `[RESTORED]`, so it never answers
    /// another receipt for the same path; only the family's `[RESTORED]` line does.
    static let memberTag = "[RESTORED·member]"

    /// What a restore did.
    public struct Restored: Sendable {
        /// false when the files moved but the receipt could not be written.
        public let receiptWritten: Bool
        public let members: Int
    }

    /// Move the Trash copy back to its original path, receipt included. The
    /// state is checked again here, right before anything moves. A family moves
    /// all of its members or none: every destination is checked first, and a
    /// failed move puts back the ones already moved.
    @discardableResult
    public static func restore(_ item: TrashedItem, trash: URL = UndoLedger.trashDir) throws -> Restored {
        let state = evaluate(original: item.originalPath, trashPath: item.trashPath, identity: item.identity,
                             receiptDate: item.receiptDate, trash: trash)
        guard state == .restorable, let trashPath = item.trashPath else { throw RestoreError.notRestorable(state) }
        let fm = FileManager.default
        var moved: [(from: String, to: String)] = []
        var receiptLines: [String] = []
        if item.isGroup {
            let parent = (item.originalPath as NSString).deletingLastPathComponent
            let names = try fm.contentsOfDirectory(atPath: trashPath)
            let plan = names.map { (from: (trashPath as NSString).appendingPathComponent($0),
                                    to: (parent as NSString).appendingPathComponent($0)) }
            for step in plan {      // check every destination before moving any
                if (try? fm.attributesOfItem(atPath: step.to)) != nil { throw RestoreError.notRestorable(.pathOccupied) }
            }
            do {
                for step in plan {
                    try fm.moveItem(atPath: step.from, toPath: step.to)
                    moved.append(step)
                }
            } catch {
                // put back what already moved; any member that cannot be put back is where the
                // restore left it, so say so in a receipt and in the error
                var leftBehind: [String] = []
                for step in moved.reversed() {
                    do { try fm.moveItem(atPath: step.to, toPath: step.from) } catch { leftBehind.append(step.to) }
                }
                if !leftBehind.isEmpty {
                    appendReceipt(leftBehind.map { "\(memberTag)  \($0)" }.joined(separator: "\n"), to: item.ledger)
                    throw RestoreError.moveFailed("\(error.localizedDescription). \(leftBehind.count) already-moved "
                        + "item\(leftBehind.count == 1 ? " stayed" : "s stayed") at the original place and could not be put back in the Trash.")
                }
                throw RestoreError.moveFailed(error.localizedDescription)
            }
            try? fm.removeItem(atPath: trashPath)   // now empty
            // one line per member under a tag the pairing ignores, then the family's own line
            receiptLines = plan.map { "\(memberTag)  \($0.to)" }
        } else {
            do {
                try fm.moveItem(atPath: trashPath, toPath: item.originalPath)
            } catch {
                throw RestoreError.moveFailed(error.localizedDescription)
            }
        }
        // the pairing line: the path the TRASHED receipt names (the token for a family)
        receiptLines.append("[RESTORED] \(item.sizeText)  \(item.originalPath)")
        let written = appendReceipt(receiptLines.joined(separator: "\n"), to: item.ledger)
        return Restored(receiptWritten: written, members: max(moved.count, 1))
    }

    @discardableResult
    private static func appendReceipt(_ text: String, to url: URL) -> Bool {
        let data = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                return true
            } catch { return false }
        }
        return (try? data.write(to: url)) != nil
    }

    // "[TAG] 1.5 MB  /path with spaces" — size is the two tokens after the
    // tag; the path is everything after the double space.
    private static func pathPart(of line: String) -> String? {
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
