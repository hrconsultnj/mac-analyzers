import Foundation
import AnalyzersKit

// `agent-runner --probe-fence` proves the fence marker's rules on folders the probe makes itself
// in a temporary folder: a fence is placed and lifted, only an empty marker is ever removed, and a
// file, a missing path or a link to a folder is refused. Nothing outside that folder is touched.

func probeFence() -> Never {
    let root = ProbeTemp.make("ma-probe-fence")
    let fm = FileManager.default
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }
    func attempt(_ work: () throws -> Void) -> String? {
        do { try work(); return nil } catch { return "\(error)" }
    }

    let folder = root.appending(path: "node_modules").path
    try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try? "x".write(toFile: folder + "/keep.txt", atomically: true, encoding: .utf8)

    check("a folder starts unfenced", !FenceMarker.isFenced(folder))
    check("fence places the marker", attempt { try FenceMarker.fence(folder) } == nil && FenceMarker.isFenced(folder))
    check("fencing twice is not an error", attempt { try FenceMarker.fence(folder) } == nil)
    check("unfence removes the marker and nothing else",
          attempt { try FenceMarker.unfence(folder) } == nil && !FenceMarker.isFenced(folder)
          && fm.fileExists(atPath: folder + "/keep.txt"))
    check("unfencing an unfenced folder is not an error", attempt { try FenceMarker.unfence(folder) } == nil)

    // a marker that holds something is not ours
    try? "important".write(toFile: folder + "/" + FenceMarker.name, atomically: true, encoding: .utf8)
    let refused = attempt { try FenceMarker.unfence(folder) }
    check("a marker with content is left alone", refused != nil && FenceMarker.isFenced(folder), refused ?? "")
    try? fm.removeItem(atPath: folder + "/" + FenceMarker.name)

    // a folder named like the marker is not ours either
    try? fm.createDirectory(atPath: folder + "/" + FenceMarker.name, withIntermediateDirectories: true)
    check("a folder named like the marker is left alone",
          attempt { try FenceMarker.unfence(folder) } != nil && fm.fileExists(atPath: folder + "/" + FenceMarker.name))
    try? fm.removeItem(atPath: folder + "/" + FenceMarker.name)

    // not a real folder
    let file = root.appending(path: "plain.txt").path
    try? "x".write(toFile: file, atomically: true, encoding: .utf8)
    check("a file can't be fenced", attempt { try FenceMarker.fence(file) } != nil)
    check("a missing path can't be fenced", attempt { try FenceMarker.fence(root.path + "/nope") } != nil)
    let link = root.appending(path: "link").path
    try? fm.createSymbolicLink(atPath: link, withDestinationPath: folder)
    check("a link to a folder can't be fenced", attempt { try FenceMarker.fence(link) } != nil
          && !fm.fileExists(atPath: folder + "/" + FenceMarker.name))

    // Fence All acts on what the screen shows, and says which; a stale check is refused
    func listed(_ name: String, _ state: FenceState) -> SpotlightFolder {
        SpotlightFolder(path: "/p/\(name)/node_modules", project: name, kind: .nodePackages, sizeBytes: 1, state: state, title: "Node.js Packages")
    }
    let shown = [listed("a", .notFenced), listed("b", .fenced), listed("c", .notFenced)]
    check("Fence All targets the folders listed as Not Fenced", FencePlan.targets(folders: shown, changed: [:]).map(\.project) == ["a", "c"])
    check("a row lifted since the check is a target, one fenced since is not",
          FencePlan.targets(folders: shown, changed: ["/p/b/node_modules": .notFenced, "/p/a/node_modules": .fenced]).map(\.project) == ["b", "c"])
    check("a folder the check never listed is never a target", !FencePlan.targets(folders: shown, changed: [:]).contains { $0.project == "new" })
    check("the confirmation names the folders it will fence",
          FencePlan.message(FencePlan.targets(folders: shown, changed: [:])).contains("in a") && FencePlan.message(FencePlan.targets(folders: shown, changed: [:])).contains("in c"))
    check("a check from this minute is fresh, one from an hour ago is stale",
          !FencePlan.isStale(finishedAt: Date()) && FencePlan.isStale(finishedAt: Date(timeIntervalSinceNow: -3600)) && FencePlan.isStale(finishedAt: nil))
    print(failures == 0 ? "\nall hold" : "\n\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}
