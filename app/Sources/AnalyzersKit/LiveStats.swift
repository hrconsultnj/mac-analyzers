import Foundation

/// Live system facts the menu reads on open — the same signals the guard
/// watches, so what you see is what the guard decides on.
public struct LiveProcess: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable { case devTool, app }

    public let pid: Int
    public let residentMB: Int
    public let rawName: String
    public let kind: Kind
    public let ppid: Int
    public var id: Int { pid }

    public init(pid: Int, residentMB: Int, rawName: String, kind: Kind, ppid: Int = 0) {
        self.pid = pid
        self.residentMB = residentMB
        self.rawName = rawName
        self.kind = kind
        self.ppid = ppid
    }

    public var isDev: Bool { kind == .devTool }

    /// Human name: glossary for dev tooling, .app bundle name for apps.
    public var friendlyName: String {
        if isDev, let known = ProcessGlossary.friendlyName(for: rawName) { return known }
        if let range = rawName.range(of: #"([^/]+)\.app"#, options: .regularExpression) {
            return String(rawName[range].dropLast(4))
        }
        // bare binary name (helpers/daemons outside .app bundles)
        return String(rawName.split(separator: " ").first.map {
            $0.split(separator: "/").last.map(String.init) ?? String($0)
        } ?? rawName)
    }

    public var residentText: String { String(format: "%.1f GB", Double(residentMB) / 1024) }
}

/// Boot-volume capacity right now (the "purgeable-aware" free-space number —
/// the same important-usage figure Finder shows, not raw df).
public struct DiskUsage: Sendable, Equatable {
    public let totalBytes: Int64
    public let freeBytes: Int64

    public var usedBytes: Int64 { totalBytes - freeBytes }
    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
    public var usedText: String { Self.gb(usedBytes) }
    public var totalText: String { Self.gb(totalBytes) }
    public var freeText: String { Self.gb(freeBytes) }

    static func gb(_ bytes: Int64) -> String {
        String(format: "%.0f GB", Double(bytes) / 1_000_000_000)
    }
}

public enum LiveStats {

    public static func diskUsage() -> DiskUsage? {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity else { return nil }
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        return DiskUsage(totalBytes: Int64(total), freeBytes: free)
    }

    /// kern.memorystatus_vm_pressure_level — 1 normal, 2 warning, ≥4 critical
    /// (the exact sysctl the guard polls each tick).
    public enum Pressure: Sendable {
        case normal, warning, critical

        public var label: String {
            switch self {
            case .normal: "Normal"
            case .warning: "Warning — compressing/swapping"
            case .critical: "CRITICAL"
            }
        }
    }

    public static func memoryPressure() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case ..<2: return .normal
        case 2..<4: return .warning
        default: return .critical
        }
    }

    /// Mirror of the guard's killable-dev-tooling regex (display-only copy —
    /// the guard's own list in memory-guard.sh stays authoritative for kills).
    private static let killablePattern =
        "(^|/)(node|npm|npx|bun|tsx|deno)( |$)|next-server|next dev|vite|esbuild|webpack|turbo|tsup|vitest|jest|playwright|headless_shell|--headless|ms-playwright"

    /// Biggest processes RIGHT NOW by resident RAM — every kind, not just dev
    /// tooling (an OrbStack helper at 3.3 GB matters as much as next-server).
    /// `minimumMB` keeps the list to rows worth a decision.
    public static func snapshot(limit: Int = 10, minimumMB: Int = 512) -> [LiveProcess] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["axo", "pid=,rss=,args="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var result: [LiveProcess] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3,
                  let pid = Int(fields[0]), pid > 500,
                  let rssKB = Int(fields[1]) else { continue }
            let rssMB = rssKB / 1024
            guard rssMB >= minimumMB else { continue }
            let args = String(fields[2])
            let isDev = args.range(of: killablePattern, options: .regularExpression) != nil
            result.append(LiveProcess(pid: pid, residentMB: rssMB,
                                      rawName: String(args.prefix(100)),
                                      kind: isDev ? .devTool : .app))
        }
        return Array(result.sorted { $0.residentMB > $1.residentMB }.prefix(limit))
    }

    /// Dev-only convenience for the Memory tab strip.
    public static func topDevProcesses(limit: Int = 3) -> [LiveProcess] {
        snapshot(limit: 24, minimumMB: 256).filter(\.isDev).prefix(limit).map { $0 }
    }

    // MARK: - helper grouping

    /// Ancestry climb stops at shells/terminals/launchd: a dev server spawned
    /// from a terminal is its own story, not "part of iTerm" — while Chrome/
    /// Code/OrbStack helpers genuinely belong under their parent app.
    private static let groupStopPattern =
        #"(^|/)-?(zsh|bash|sh|fish|login|tmux|screen|launchd)( |$)|iTerm|Apple Terminal|Terminal\.app"#

    public static func groupedSnapshot(limit: Int = 30, minimumMB: Int = 128) -> [ProcessGroup] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["axo", "pid=,ppid=,rss=,args="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        struct Entry { let pid: Int; let ppid: Int; let rssMB: Int; let args: String }
        var table: [Int: Entry] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int(fields[0]), pid > 1,
                  let ppid = Int(fields[1]),
                  let rssKB = Int(fields[2]) else { continue }
            table[pid] = Entry(pid: pid, ppid: ppid, rssMB: rssKB / 1024,
                               args: String(fields[3]))
        }

        func isStopParent(_ args: String) -> Bool {
            args.range(of: groupStopPattern, options: .regularExpression) != nil
        }

        func rootAncestor(of pid: Int) -> Int {
            var current = pid
            var hops = 0
            while hops < 25,
                  let entry = table[current], entry.ppid > 1,
                  let parent = table[entry.ppid], !isStopParent(parent.args) {
                current = entry.ppid
                hops += 1
            }
            return current
        }

        func liveProcess(_ e: Entry) -> LiveProcess {
            let isDev = e.args.range(of: killablePattern, options: .regularExpression) != nil
            return LiveProcess(pid: e.pid, residentMB: e.rssMB,
                               rawName: String(e.args.prefix(100)),
                               kind: isDev ? .devTool : .app, ppid: e.ppid)
        }

        let heavy = table.values.filter { $0.rssMB >= minimumMB && $0.pid > 500 }
        var buckets: [Int: [Entry]] = [:]
        for entry in heavy {
            buckets[rootAncestor(of: entry.pid), default: []].append(entry)
        }

        var groups: [ProcessGroup] = []
        for (rootPid, members) in buckets {
            let parent = table[rootPid] ?? members.max { $0.rssMB < $1.rssMB }!
            let children = members.filter { $0.pid != parent.pid }
                .sorted { $0.rssMB > $1.rssMB }
            groups.append(ProcessGroup(parent: liveProcess(parent),
                                       children: children.map(liveProcess)))
        }
        return groups.sorted { $0.totalMB > $1.totalMB }.prefix(limit).map { $0 }
    }
}

/// A parent process with its heavy helpers rolled underneath — the Monitor
/// pane's Activity-Monitor-beating view: one row per APP, expandable.
public struct ProcessGroup: Identifiable, Sendable {
    public let parent: LiveProcess
    public let children: [LiveProcess]
    public var id: Int { parent.pid }

    public init(parent: LiveProcess, children: [LiveProcess]) {
        self.parent = parent
        self.children = children
    }

    public var totalMB: Int { parent.residentMB + children.map(\.residentMB).reduce(0, +) }
    public var totalText: String { String(format: "%.1f GB", Double(totalMB) / 1024) }
}
