import Foundation

/// A fence is one empty file, `.metadata_never_index`, in a folder: Spotlight skips the folder
/// (and everything in it) while it is there. Placing and lifting one is the app's own small
/// action on a single folder — nothing is moved or deleted but that file — so it is done here
/// directly and is reversible by the other half of this type.
public enum FenceMarker {

    public static let name = ".metadata_never_index"

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAFolder(String)
        case notOurs(String)
        case couldNotChange(String)

        public var description: String {
            switch self {
            case .notAFolder(let path): "\(StorageLog.short(path)) is not a folder, so it can't be fenced."
            case .notOurs(let path): "The file in \(StorageLog.short(path)) is not an empty fence marker, so it was left alone."
            case .couldNotChange(let path): "Couldn't change the fence on \(StorageLog.short(path))."
            }
        }
    }

    static func marker(in folder: String) -> String { (folder as NSString).appendingPathComponent(name) }

    private static func isRealFolder(_ path: String) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.type] as? FileAttributeType) == .typeDirectory     // a symlink to a folder is not one
    }

    public static func isFenced(_ folder: String) -> Bool {
        FileManager.default.fileExists(atPath: marker(in: folder))
    }

    /// Puts the marker in `folder`. Already fenced is not an error.
    public static func fence(_ folder: String) throws {
        guard isRealFolder(folder) else { throw Failure.notAFolder(folder) }
        guard !isFenced(folder) else { return }
        guard FileManager.default.createFile(atPath: marker(in: folder), contents: Data()) else {
            throw Failure.couldNotChange(folder)
        }
    }

    /// Removes the marker, and only a marker: a regular, empty file of that name. Anything else
    /// (a folder, a file with content, a link) is not ours and stays.
    public static func unfence(_ folder: String) throws {
        let path = marker(in: folder)
        guard isRealFolder(folder) else { throw Failure.notAFolder(folder) }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return }  // not fenced
        guard (attributes[.type] as? FileAttributeType) == .typeRegular, (attributes[.size] as? Int) == 0 else {
            throw Failure.notOurs(folder)
        }
        // unlink refuses a directory by itself, so a folder swapped in after the check above is never removed
        guard unlink(path) == 0 else { throw Failure.couldNotChange(folder) }
    }
}

/// Fence All: what it acts on is what the screen shows, nothing else. The check's folders whose
/// state on screen (the check's own, or what a row since put there) is Not Fenced, named in the
/// confirmation, refused when the check is too old. The old way reran the audit script, which
/// scans again: it fenced folders created since and the ones the person had just unfenced, under
/// a confirmation that described something else.
public enum FencePlan {

    /// The folders Fence All would fence.
    public static func targets(folders: [SpotlightFolder], changed: [String: FenceState]) -> [SpotlightFolder] {
        folders.filter { (changed[$0.path] ?? $0.state) == .notFenced }
    }

    /// A check older than the review window no longer describes the folders.
    public static func isStale(finishedAt: Date?, now: Date = Date()) -> Bool {
        guard let finishedAt else { return true }
        return now.timeIntervalSince(finishedAt) > JobStore.reviewWindow
    }

    public static let staleMessage = "That check is more than 15 minutes old, so the folders it listed may have changed. Check again to see them now."

    public static func title(count: Int) -> String {
        count == 1 ? "Fence 1 Folder?" : "Fence \(count) Folders?"
    }

    /// Names the folders: "node_modules in etal, node_modules in nutri-journey, and 9 more".
    public static func message(_ targets: [SpotlightFolder]) -> String {
        let names = targets.map { "\($0.title) in \($0.project)" }
        let listed = ReviewWording.nameList(names, noun: "folders")
        return "Places an empty .metadata_never_index file in \(listed), so Spotlight stops indexing \(targets.count == 1 ? "it" : "them"). Nothing is moved or deleted, and each fence can be lifted here or by deleting that file."
    }
}
