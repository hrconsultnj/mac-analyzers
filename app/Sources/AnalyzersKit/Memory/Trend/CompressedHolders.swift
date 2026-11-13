import Foundation

/// Who holds the most compressed memory, read from `/usr/bin/top`.
///
/// No per-process compressed figure can be read from a process of another account (the API has none, and the task port that
/// would give it cannot be had). `top` is Apple's own tool and holds the entitlement that lets it, so it prints MEM and CMPRS
/// for every process with no root. We run it ONCE when a screen asks (about 0.7 s, mostly system time), never on a timer,
/// and read what it prints. Its format is documented in `man top` (`-stats`) but is not an API, so the parse refuses what it
/// does not understand and the screen says so instead of showing a wrong table.
public struct CompressedHolder: Sendable, Identifiable, Equatable {
    public let pid: Int
    /// The name `top` gives (cut at 16 characters by `top` itself).
    public let command: String
    /// The process's footprint (what Activity Monitor's Memory column shows).
    public let footprintBytes: Int64
    /// Of that footprint, what sits compressed or swapped.
    public let compressedBytes: Int64
    public let user: String
    public var id: Int { pid }
}

public struct CompressedHoldersReading: Sendable {
    public let holders: [CompressedHolder]
    public let readAt: Date
    /// Why nothing could be read, when so.
    public let failure: String?
}

public enum CompressedHolders {

    /// How many rows to ask `top` for, biggest compressed first.
    public static let limit = 40

    /// Runs `top` and parses it. Off the main thread: it takes under a second, and this waits for it.
    public static func read(limit: Int = CompressedHolders.limit, timeout: TimeInterval = 20) -> CompressedHoldersReading {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = ["-l", "1", "-n", String(limit), "-o", "cmprs", "-stats", "pid,command,mem,cmprs,user"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            return CompressedHoldersReading(holders: [], readAt: Date(), failure: "top could not be started")
        }
        // what top prints with -n 40 is a few kilobytes, far under the pipe's buffer, so it can be read after it ends
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            return CompressedHoldersReading(holders: [], readAt: Date(), failure: "top took too long")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let holders = parse(String(decoding: data, as: UTF8.self))
        return CompressedHoldersReading(holders: holders, readAt: Date(),
                                        failure: holders.isEmpty ? "top printed nothing this screen could read" : nil)
    }

    /// The table `top` prints after its header line `PID COMMAND MEM CMPRS USER`: the command may hold spaces, so a row
    /// is read from both ends (the pid first; user, compressed and memory last).
    public static func parse(_ text: String) -> [CompressedHolder] {
        var found: [CompressedHolder] = []
        var inTable = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if !inTable {
                let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                inTable = words == ["PID", "COMMAND", "MEM", "CMPRS", "USER"]
                continue
            }
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard words.count >= 5, let pid = Int(words[0]),
                  let footprint = bytes(words[words.count - 3]), let compressed = bytes(words[words.count - 2])
            else { continue }
            found.append(CompressedHolder(pid: pid, command: words[1..<(words.count - 3)].joined(separator: " "),
                                          footprintBytes: footprint, compressedBytes: compressed, user: words[words.count - 1]))
        }
        return found
    }

    /// "7904K", "6594M", "1G", "512B", each with an optional trailing `+` or `-` (a change marker).
    static func bytes(_ word: String) -> Int64? {
        var text = word
        if let last = text.last, last == "+" || last == "-" { text.removeLast() }
        guard let unit = text.last else { return nil }
        let scale: Double
        switch unit {
        case "B": scale = 1
        case "K": scale = 1_024
        case "M": scale = 1_048_576
        case "G": scale = 1_073_741_824
        case "T": scale = 1_099_511_627_776
        default:
            return Double(text).map { Int64($0) }
        }
        guard let number = Double(text.dropLast()) else { return nil }
        return Int64(number * scale)
    }
}
