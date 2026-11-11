import AppKit
import Foundation

/// One process in a network snapshot, ready for a table row.
public struct NetworkProcessRow: Identifiable, Hashable, Sendable {
    public let id: String
    /// The app or process, named for a person.
    public let name: String
    public let pid: Int
    public let downloaded: Int64
    public let uploaded: Int64
    /// This process's share of everything the snapshot counted (0...1).
    public let share: Double
    /// True when the process is still running now.
    public let isRunning: Bool
    /// True for an app you can see in the Dock or menu bar, false for a
    /// background process.
    public let isApp: Bool
    /// Where the program lives, while it is still running.
    public let path: String?
    /// The app it works for ("Tailscale" for its helper too), or its own name.
    public let group: String

    public var total: Int64 { downloaded + uploaded }
    public var kindTitle: String { isApp ? "App" : "Background" }
}

/// One saved network snapshot: when, the totals, and who moved the most.
public struct NetworkSnapshotRun: Identifiable, Hashable, Sendable {
    public let id: String
    public let date: Date
    public let totalDownloaded: Int64
    public let totalUploaded: Int64
    public let talkers: [NetworkTalker]

    public var processCount: Int { talkers.count }

    /// The busiest process in the snapshot, named from what the log recorded.
    public var busiest: String? {
        talkers.max { $0.totalBytes < $1.totalBytes }
            .map { Self.readable(ProcessGlossary.friendlyName(for: $0.name) ?? $0.name, pid: nil) }
    }

    /// nettop names some programs by their version folder ("2.1.322"). A name
    /// that is only digits and dots is replaced by the nearest folder of the
    /// program's path that is a word ("claude"), when the process is running.
    static func executablePath(pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func readable(_ name: String, pid: Int?) -> String {
        guard name.allSatisfy({ $0.isNumber || $0 == "." }) else { return name }
        guard let pid else { return "Unnamed program \(name)" }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return "Unnamed program \(name)" }
        let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let words = path.split(separator: "/").dropLast().reversed()
        let skip: Set<String> = ["versions", "bin", "lib", "libexec", "current", "latest"]
        if let word = words.first(where: { part in
            !skip.contains(part.lowercased()) && !part.allSatisfy { $0.isNumber || $0 == "." }
        }) {
            return String(word)
        }
        return "Unnamed program \(name)"
    }

    /// The table rows. With `resolving`, names and "running" come from what
    /// is running now; without it (an older snapshot) only what was saved.
    public func rows(resolving: Bool, census: MemoryCensus? = nil) -> [NetworkProcessRow] {
        // Monitor's own naming: the process is the one the census knows by pid,
        // and its app is the census group that holds it
        var known: [Int: (name: String, group: String)] = [:]
        if resolving, let census {
            for group in census.groups {
                for member in group.members { known[member.pid] = (member.friendlyName, group.name) }
            }
        }
        let grand = max(1, talkers.reduce(0) { $0 + $1.totalBytes })
        return talkers.map { talker in
            let app = NSRunningApplication(processIdentifier: pid_t(talker.pid))
            // Only the newest snapshot can say what is running: a pid in an
            // older one may belong to a different process by now.
            // the logged name and the snapshot's own time: a pid reused by another
            // program, or one that started after the snapshot, is not this program
            // (the log's time is to the minute, so the whole minute counts)
            let live = resolving
                && ProcessLiveness.isStillRunning(pid: talker.pid, name: talker.name,
                                                  loggedAt: date.addingTimeInterval(60))
            let fromCensus = live ? known[talker.pid] : nil
            let displayName = fromCensus?.name ?? Self.readable(live ? talker.resolvedName
                : (ProcessGlossary.friendlyName(for: talker.name) ?? talker.name), pid: live ? talker.pid : nil)
            let livePath = live ? (app?.bundleURL?.path ?? Self.executablePath(pid: talker.pid)) : nil
            return NetworkProcessRow(
                id: "\(id)#\(talker.id)",
                name: displayName,
                pid: talker.pid,
                downloaded: talker.inBytes, uploaded: talker.outBytes,
                share: Double(talker.totalBytes) / Double(grand),
                isRunning: live,
                isApp: live && app != nil,
                path: livePath,
                group: fromCensus?.group
                    ?? livePath.flatMap(StartupNaming.outermostApp(in:)).map(StartupNaming.appName(at:)) ?? displayName)
        }
    }
}

public enum NetworkSnapshotHistory {

    /// Every snapshot in the log, newest first.
    public static func read(at url: URL = AnalyzersPaths.networkLog, limit: Int = 60) -> [NetworkSnapshotRun] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm"

        var runs: [NetworkSnapshotRun] = []
        var sameMinute: [String: Int] = [:]
        for block in text.components(separatedBy: "================================================================")
        where block.contains("| network snapshot |") {
            guard let snapshot = NetworkParser.parse(block: block),
                  let date = stamp.date(from: String(snapshot.header.prefix(16))) else { continue }
            let minute = String(snapshot.header.prefix(16))
            let n = sameMinute[minute, default: 0]
            sameMinute[minute] = n + 1
            runs.append(NetworkSnapshotRun(
                id: n == 0 ? minute : "\(minute)#\(n)",
                date: date,
                totalDownloaded: snapshot.totalIn, totalUploaded: snapshot.totalOut,
                talkers: snapshot.talkers))
        }
        return Array(runs.reversed().prefix(limit))
    }
}

/// One app and every program of its that moved data: the parent row that opens
/// to its members.
public struct NetworkGroup: Identifiable, Hashable, Sendable {
    public let name: String
    public let rows: [NetworkProcessRow]

    public var id: String { "group:\(name)" }
    public var count: Int { rows.count }
    public var countText: String { "\(count) \(count == 1 ? "program" : "programs")" }
    public var downloaded: Int64 { rows.reduce(0) { $0 + $1.downloaded } }
    public var uploaded: Int64 { rows.reduce(0) { $0 + $1.uploaded } }
    public var total: Int64 { downloaded + uploaded }
    public var share: Double { rows.reduce(0) { $0 + $1.share } }
    public var runningCount: Int { rows.filter(\.isRunning).count }

    /// The groups of a snapshot's rows, busiest first.
    public static func groups(of rows: [NetworkProcessRow]) -> [NetworkGroup] {
        Dictionary(grouping: rows, by: \.group)
            .map { NetworkGroup(name: $0.key, rows: $0.value.sorted { $0.total > $1.total }) }
            .sorted { $0.total > $1.total }
    }

    /// Problems with the shape: a name that repeats inside a group.
    public static func problems(in groups: [NetworkGroup]) -> [String] {
        groups.flatMap { group in
            let names = group.rows.map(\.name)
            return Set(names).filter { name in names.filter { $0 == name }.count > 1 }
                .map { "\(group.name): \"\($0)\" appears more than once" }
        }
    }
}
