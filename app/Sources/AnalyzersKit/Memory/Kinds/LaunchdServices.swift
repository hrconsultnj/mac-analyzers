import Foundation

/// The processes launchd is running for the launch agents and daemons installed outside macOS: pid → the job's label.
/// A process is a background service only when it IS the process launchd reports for one of these jobs. The job's
/// executable is not enough: a job that runs `node` says nothing about any other `node`, and an orphan of one (its
/// parent is launchd too) is not restarted by anyone.
///
/// The jobs come from the property lists in the folders launchd reads; the pids from `launchctl list` (read only:
/// it launches nothing and changes nothing).
enum LaunchdServices {

    /// Labels of the jobs installed outside macOS.
    static func labels() -> Set<String> {
        let folders = [AnalyzersPaths.home.appending(path: "Library/LaunchAgents"),
                       URL(filePath: "/Library/LaunchAgents"), URL(filePath: "/Library/LaunchDaemons")]
        var found = Set<String>()
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: file),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                      let label = plist["Label"] as? String else { continue }
                found.insert(label)
            }
        }
        return found
    }

    /// `launchctl list` prints `PID<TAB>Status<TAB>Label`, with `-` for a job that is not running.
    static func parse(_ output: String, labels: Set<String>) -> [Int: String] {
        var jobs: [Int: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, let pid = Int(fields[0]), pid > 0 else { continue }
            let label = String(fields[2])
            if labels.contains(label) { jobs[pid] = label }
        }
        return jobs
    }

    static func jobs() -> [Int: String] {
        let labels = labels()
        guard !labels.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        // the census waits on this: never on a stuck child
        let child = process.processIdentifier
        let watchdog = DispatchWorkItem { kill(child, SIGKILL) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parse(String(decoding: data, as: UTF8.self), labels: labels)
    }
}
