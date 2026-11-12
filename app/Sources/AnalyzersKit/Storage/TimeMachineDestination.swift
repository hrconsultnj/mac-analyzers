import Foundation

/// Whether the Time Machine backup disk can be reached right now, read with `tmutil destinationinfo`, which only
/// reads. Used by the confirmation before local snapshots are deleted: while the disk is not connected, those
/// snapshots can be the only copies of recent versions of a person's files.
public enum TimeMachineDestination {

    public enum Reach: Equatable, Sendable {
        /// At least one backup disk is mounted.
        case connected
        /// Backup disks are set up and none is mounted now.
        case notConnected
        /// Time Machine has no backup disk.
        case notSetUp
        /// `tmutil` could not be asked, or said something this does not read.
        case unknown
    }

    /// Reads `tmutil destinationinfo`'s text: one block per destination, a `Mount Point` line only while it is mounted.
    public static func reach(from output: String) -> Reach {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let names = lines.filter { $0.hasPrefix("Name") && $0.contains(":") }
        if names.isEmpty { return output.localizedCaseInsensitiveContains("no destinations") ? .notSetUp : .unknown }
        return lines.contains { $0.hasPrefix("Mount Point") && $0.contains(":") } ? .connected : .notConnected
    }

    /// Asks `tmutil` (a parameter for a probe), with the permission path's clean environment.
    public static func current(tmutil: String = "/usr/bin/tmutil") async -> Reach {
        await Task.detached(priority: .userInitiated) { () -> Reach in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmutil)
            process.arguments = ["destinationinfo"]
            process.environment = TimeMachinePermission.cleanEnvironment
            let output = Pipe()
            process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return .unknown }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            // "No destinations configured" comes with a failing status; anything else failing is not an answer
            if process.terminationStatus != 0 && !text.localizedCaseInsensitiveContains("no destinations") { return .unknown }
            return reach(from: text)
        }.value
    }
}
