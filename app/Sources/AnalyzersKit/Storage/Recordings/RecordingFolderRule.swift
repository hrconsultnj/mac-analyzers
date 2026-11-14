import Foundation

/// The folders that can never be a recording source, whatever the settings say. The Sources window refuses them
/// first, with the sentence below; the engine (`cleanup.sh`, `rec_refusal`) refuses the same ones again, so a hand-edited
/// config.local.sh cannot point a cleanup at the home folder. `agent-runner --probe-recordings-engine` checks that the
/// two sides refuse the same paths.
public enum RecordingFolderRule {

    /// Why `path` cannot be a source, or nil when it can. `isLink` is whether the path itself is a symbolic link.
    public static func refusal(_ path: String, layout: RecordingSourceDefinition.Layout = .folders, home: String,
                               isLink: Bool) -> String? {
        guard path.hasPrefix("/") else { return "it is not a full path" }
        if path.contains("\t") || path.contains("\n") { return "its name holds a tab or a line break" }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains("..") || parts.contains(".") { return "it is not a plain path" }
        if path == "/" || path == home { return "it is your whole home folder or the whole disk" }
        if path.hasPrefix("/Volumes/"), !path.dropFirst("/Volumes/".count).contains("/") { return "it is a whole disk" }
        for name in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Library"]
        where path == "\(home)/\(name)" && layout != .files {
            return "it is your whole \(name) folder, which holds more than recordings; choose a folder inside it"
        }
        for name in ["CloudStorage", "Mobile Documents", "Containers", "Group Containers"] {
            let root = "\(home)/Library/\(name)"
            if path == root || path.hasPrefix(root + "/") {
                return "it syncs to the cloud or belongs to another app, which keeps its own library there"
            }
        }
        if isLink { return "it is a link to another folder, and a link is not followed" }
        return nil
    }
}
