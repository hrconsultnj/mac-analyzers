import Foundation

/// Where a recording source may be, and what can never be one. A source must be INSIDE the person's home folder
/// (leaving out hidden folders, and the Library except a folder a known recording app names in
/// `lib/recording-sources.tsv`) or on an external disk (`/Volumes/<disk>/…`). Everything else is refused: the
/// system, other users, an app's data, the cloud. A standard folder (Documents, Desktop, Downloads, Movies, Music,
/// Pictures) is refused as a whole source for folders (a folder inside it is fine), and a link is refused.
///
/// The check runs on the path as written AND on where it really leads, so a link in the middle of a path cannot walk
/// round it. The Sources window refuses first, with the sentence below; the engine (`cleanup.sh`, `rec_refusal`) makes
/// the same check again, so a hand-edited config.local.sh cannot point a cleanup at the wrong place.
/// `agent-runner --probe-recordings-engine` checks that the two sides refuse the same paths.
public enum RecordingFolderRule {

    public static let standardFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Library"]

    /// Why `path` cannot be a source, or nil when it can. `isLink` is whether the path itself is a symbolic link;
    /// `resolved` is where the path really leads (nil when it is not known, or does not exist). No file is touched.
    public static func refusal(_ path: String, layout: RecordingSourceDefinition.Layout = .folders, home: String,
                               homeResolved: String? = nil, isLink: Bool = false, resolved: String? = nil,
                               libraryFolders: [String] = libraryFoldersOfKnownApps()) -> String? {
        guard path.hasPrefix("/") else { return "it is not a full path" }
        if path.contains("\t") || path.contains("\n") { return "its name holds a tab or a line break" }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains("..") || parts.contains(".") { return "it is not a plain path" }
        let roots = [home, homeResolved].compactMap { $0 }
        if let why = check(path, layout: layout, roots: roots, libraryFolders: libraryFolders) { return why }
        if isLink { return "it is a link to another folder, and a link is not followed" }
        if let resolved, resolved != path, let why = check(resolved, layout: layout, roots: roots, libraryFolders: libraryFolders) {
            return "it leads through a link to \(resolved), and \(why)"
        }
        return nil
    }

    /// The Library folders the list of known recording apps names (none today): the only ones allowed under `~/Library`.
    public static func libraryFoldersOfKnownApps() -> [String] {
        RecordingSourceCatalog.definitions.flatMap { definition in
            definition.findBy.compactMap { step -> String? in
                if case .home(let path) = step.kind, path.hasPrefix("Library/") { return path }
                return nil
            }
        }
    }

    private static func check(_ path: String, layout: RecordingSourceDefinition.Layout, roots: [String],
                              libraryFolders: [String]) -> String? {
        if path == "/" { return "it is the whole disk" }
        for root in roots {
            let rel: String
            if path == root { rel = "" } else if path.hasPrefix(root + "/") { rel = String(path.dropFirst(root.count + 1)) } else { continue }
            if rel.isEmpty { return "it is your whole home folder" }
            let first = String(rel.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0])
            if first.hasPrefix(".") { return "it is in a hidden folder of your home folder, where settings and keys are kept" }
            if first == "Library", !libraryFolders.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
                return "it is in your Library folder, where apps keep their own data and your cloud storage"
            }
            if standardFolders.contains(rel), layout != .files {
                return "it is your whole \(rel) folder, which holds more than recordings; choose a folder inside it"
            }
            return nil
        }
        if path.hasPrefix("/Volumes/") {
            return path.dropFirst("/Volumes/".count).contains("/") ? nil : "it is a whole disk"
        }
        return "it is outside your home folder and your external disks"
    }
}
