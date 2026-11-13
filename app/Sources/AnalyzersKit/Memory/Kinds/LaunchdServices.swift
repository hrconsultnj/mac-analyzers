import Foundation

/// The programs launchd is set up to keep running, read from the launch agents and daemons installed outside
/// macOS: executable path → the job's label. A process that launchd started from one of these is a background
/// service, and stopping it only makes launchd start it again. Read from the property lists (the folders
/// launchd itself reads), so nothing is started to ask.
enum LaunchdServices {

    static func programs() -> [String: String] {
        let folders = [AnalyzersPaths.home.appending(path: "Library/LaunchAgents"),
                       URL(filePath: "/Library/LaunchAgents"), URL(filePath: "/Library/LaunchDaemons")]
        var found: [String: String] = [:]
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: file),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                      let label = plist["Label"] as? String else { continue }
                let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
                if let program, program.hasPrefix("/"), found[program] == nil { found[program] = label }
            }
        }
        return found
    }
}
