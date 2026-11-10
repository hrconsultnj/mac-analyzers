import Darwin
import Foundation
import os

/// Footprints of the processes the kernel won't size for an ordinary app:
/// macOS's own daemons, owned by root and service accounts. `top` ships with
/// the system and is permitted to read them, so one short run fills the gap.
///
/// Cached: those daemons change slowly, and a 5-second refresh has no reason
/// to launch a tool every tick to re-read them.
enum PrivilegedFootprints {

    private static let cache = OSAllocatedUnfairLock<(stamp: Date, values: [Int32: Int64])>(
        initialState: (.distantPast, [:]))

    static func current(maxAge: TimeInterval = 30) -> [Int32: Int64] {
        let cached = cache.withLock { $0 }
        if Date().timeIntervalSince(cached.stamp) < maxAge { return cached.values }
        let fresh = read()
        // an empty read is cached too — a failing tool isn't retried every tick
        cache.withLock { $0 = (Date(), fresh) }
        return fresh
    }

    private static func read() -> [Int32: Int64] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = ["-l", "1", "-n", "5000", "-stats", "pid,mem"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }

        // this runs on the app's one serialized loader — never let it wait
        // on a stuck child
        let child = process.processIdentifier
        let watchdog = DispatchWorkItem { kill(child, SIGKILL) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Rows after the "PID MEM" header: `24423  675M+`.
    static func parse(_ output: String) -> [Int32: Int64] {
        var values: [Int32: Int64] = [:]
        var inTable = false
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2 else { continue }
            if fields[0] == "PID" { inTable = true; continue }
            guard inTable, let pid = Int32(fields[0]), let bytes = size(fields[1]) else { continue }
            values[pid] = bytes
        }
        return values
    }

    private static func size(_ field: Substring) -> Int64? {
        // a trailing +/- marks growth since the last sample
        let trimmed = field.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let unit = trimmed.last, let value = Double(trimmed.dropLast()) else { return nil }
        let multiplier: Double
        switch unit {
        case "B": multiplier = 1
        case "K": multiplier = 1024
        case "M": multiplier = 1_048_576
        case "G": multiplier = 1_073_741_824
        case "T": multiplier = 1_099_511_627_776
        default: return nil
        }
        return Int64(value * multiplier)
    }
}
