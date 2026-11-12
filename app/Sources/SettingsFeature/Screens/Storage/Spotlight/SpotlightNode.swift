import AnalyzersKit
import Foundation

/// One line of the Spotlight table: a project (a group with its count and total) or one folder
/// in it with its fence. Built from the audit's `SpotlightFolder`s and the fences changed since.
struct SpotlightNode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let bytes: Int64?
    /// nil for a project.
    let state: FenceState?
    let path: String?
    var children: [SpotlightNode]?

    var isGroup: Bool { children != nil }
    var sortBytes: Int64 { bytes ?? -1 }
    var sortName: String { title }
    var sortState: Int { state == .notFenced ? 0 : 1 }

    /// The projects, biggest first, each holding its folders biggest first. `changed` carries the
    /// fences placed or lifted on this screen since the audit.
    static func tree(_ folders: [SpotlightFolder], changed: [String: FenceState]) -> [SpotlightNode] {
        var order: [String] = []
        var byProject: [String: [SpotlightFolder]] = [:]
        for folder in folders {
            if byProject[folder.project] == nil { order.append(folder.project) }
            byProject[folder.project, default: []].append(folder)
        }
        return order.map { project -> SpotlightNode in
            let members = (byProject[project] ?? []).map { folder -> SpotlightNode in
                let state = changed[folder.path] ?? folder.state
                return SpotlightNode(id: folder.path, title: folder.title, detail: StorageLog.short(folder.path),
                                     bytes: folder.sizeBytes, state: state, path: folder.path, children: nil)
            }.sorted { $0.sortBytes > $1.sortBytes }
            let open = members.filter { $0.state == .notFenced }.count
            let total = members.compactMap(\.bytes).reduce(0, +)
            let counted = "\(members.count) \(members.count == 1 ? "folder" : "folders")"
            return SpotlightNode(id: "project:\(project)", title: project,
                                 detail: open == 0 ? "\(counted) · all fenced" : "\(counted) · \(open) not fenced",
                                 bytes: total, state: nil, path: nil, children: members)
        }.sorted { $0.sortBytes > $1.sortBytes }
    }

    /// Every folder under these ids: a folder is itself, a project is its folders.
    static func folders(under ids: Set<String>, in tree: [SpotlightNode]) -> [SpotlightNode] {
        var found: [SpotlightNode] = []
        for node in tree {
            if let children = node.children {
                if ids.contains(node.id) { found += children }
                else { found += children.filter { ids.contains($0.id) } }
            }
        }
        return found
    }
}
