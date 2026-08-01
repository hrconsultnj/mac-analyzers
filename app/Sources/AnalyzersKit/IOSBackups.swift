import AppKit
import Foundation

/// Finds local iPhone/iPad backups (MobileSync) — often multi-GB and
/// forgotten. REPORT ONLY: the app never deletes a backup; rows open in
/// Finder so removal stays a deliberate, manual act.
public struct IOSBackup: Identifiable, Sendable {
    public let url: URL
    public let deviceName: String
    public let lastBackup: Date?
    public let sizeBytes: Int64

    public var id: String { url.path }
}

public enum IOSBackups {

    public static let backupsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/MobileSync/Backup")

    /// Blocking (du per backup) — call off the main thread.
    public static func scan() -> [IOSBackup] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: backupsRoot,
                                                     includingPropertiesForKeys: nil)
        else { return [] }

        var result: [IOSBackup] = []
        for dir in dirs where dir.hasDirectoryPath {
            let info = NSDictionary(contentsOf: dir.appending(path: "Info.plist"))
            let name = info?["Device Name"] as? String
                ?? info?["Display Name"] as? String
                ?? dir.lastPathComponent
            let date = info?["Last Backup Date"] as? Date
            result.append(IOSBackup(url: dir, deviceName: name,
                                    lastBackup: date, sizeBytes: dirSize(dir)))
        }
        return result.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func dirSize(_ url: URL) -> Int64 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let kb = Int64(String(data: data, encoding: .utf8)?
            .split(separator: "\t").first.map(String.init) ?? "") ?? 0
        return kb * 1024
    }

    public static func revealInFinder(_ backup: IOSBackup) {
        NSWorkspace.shared.activateFileViewerSelecting([backup.url])
    }
}
