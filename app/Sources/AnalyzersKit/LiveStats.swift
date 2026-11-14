import Foundation

/// Live queries over the process table, memory pressure and the boot volume.
///
/// This file is the queries only. The values they return live next to it:
///   LiveProcess.swift   one process, and a parent with its helpers (ProcessGroup)
///   MemorySize.swift    the one formatter for memory figures
///   DiskUsage.swift     boot-volume capacity
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

    /// Biggest processes RIGHT NOW by resident RAM — every kind, not just dev
    /// tooling (an OrbStack helper at 3.3 GB matters as much as next-server).
    /// `minimumMB` keeps the list to rows worth a decision.
    /// One sweep, three views. The store used to ask for the top processes,
    /// the full snapshot and the grouped families separately — three walks
    /// of the same table per refresh, for data that must agree anyway.
    public struct Sample: Sendable {
        public let top: [LiveProcess]
        public let all: [LiveProcess]
        public let groups: [ProcessGroup]
    }

    public static func sample(minimumMB: Int = 128) -> Sample {
        let raw = ProcTable.sweep(minimumMB: min(minimumMB, 32))
        let processes = raw.map { entry in
            LiveProcess(pid: entry.pid, residentMB: entry.residentMB,
                        rawName: CommandLineDisplay.shown(entry.command),
                        kind: isDevTooling(entry.command) ? .devTool : .app,
                        ppid: entry.ppid, identity: ProcessIdentity.of(pid: entry.pid))
        }.sorted { $0.residentMB > $1.residentMB }

        return Sample(
            top: processes.filter { $0.isDev && $0.residentMB >= 256 }.prefix(3).map { $0 },
            all: processes.filter { $0.residentMB >= 512 }.prefix(10).map { $0 },
            groups: group(raw, limit: 14, minimumMB: 256))
    }

    public static func snapshot(limit: Int = 10, minimumMB: Int = 512) -> [LiveProcess] {
        // fork-free: the kernel answers this directly (see ProcTable)
        let result = ProcTable.sweep(minimumMB: minimumMB).map { raw in
            LiveProcess(pid: raw.pid, residentMB: raw.residentMB,
                        rawName: CommandLineDisplay.shown(raw.command),
                        kind: isDevTooling(raw.command) ? .devTool : .app,
                        ppid: raw.ppid, identity: ProcessIdentity.of(pid: raw.pid))
        }
        return Array(result.sorted { $0.residentMB > $1.residentMB }.prefix(limit))
    }

    /// Whether a command line is developer tooling, by the kind the catalog gives it (`kinds.json`). The one
    /// reading: the guard's old text pattern is gone from the app, and the engine's own list stays in the script.
    public static func isDevTooling(_ command: String) -> Bool {
        KindCatalog.current.isDevTooling(command: command)
    }

    /// Dev-only convenience for the Memory tab strip.
    public static func topDevProcesses(limit: Int = 3) -> [LiveProcess] {
        snapshot(limit: 24, minimumMB: 256).filter(\.isDev).prefix(limit).map { $0 }
    }

    /// One process by pid, at ANY size and whoever owns it — the dossier's
    /// lookup. The ranked lists above only carry the biggest rows, so a small
    /// or system-owned process read from them looked "not running".
    public static func process(pid: Int) -> LiveProcess? {
        guard pid > 0, pid <= Int(Int32.max) else { return nil }
        let pid32 = Int32(pid)
        guard let identity = ProcTable.identity(of: pid32) else { return nil }
        let usage = ProcTable.usage(of: pid32)
        let footprint = usage.map { Int64($0.footprint) }
            ?? PrivilegedFootprints.current()[pid32]
        let command = ProcTable.commandLine(of: pid32)
        let isDev = isDevTooling(command)
        let path = ProcTable.executablePath(of: pid32)
        return LiveProcess(pid: pid,
                           residentMB: Int((usage?.resident ?? 0) / 1_048_576),
                           rawName: CommandLineDisplay.shown(command),
                           kind: isDev ? .devTool : .app,
                           ppid: identity.ppid,
                           footprintBytes: footprint,
                           // its own name, as the census rows show it
                           label: isDev || path.hasPrefix("pid ")
                               ? nil : (path as NSString).lastPathComponent,
                           canQuit: identity.uid == getuid()
                               && !MemoryCensus.isSystemPath(path),
                           identity: ProcessIdentity.of(pid: pid))
    }

    // MARK: - helper grouping

    /// Ancestry climb stops at shells/terminals/launchd: a dev server spawned
    /// from a terminal is its own story, not "part of iTerm" — while Chrome/
    /// Code/OrbStack helpers genuinely belong under their parent app.
    static let groupStopPattern =
        #"(^|/)-?(zsh|bash|sh|fish|login|tmux|screen|launchd)( |$)|iTerm|Apple Terminal|Terminal\.app"#

    /// Family grouping over an ALREADY-swept table, so callers that need
    /// several views of the process list pay for one sweep, not three.
    public static func group(_ sweep: [RawProc], limit: Int, minimumMB: Int) -> [ProcessGroup] {
        struct Entry { let pid: Int; let ppid: Int; let rssMB: Int; let args: String }
        var table: [Int: Entry] = [:]
        for raw in sweep {
            table[raw.pid] = Entry(pid: raw.pid, ppid: raw.ppid,
                                   rssMB: raw.residentMB, args: raw.command)
        }
        // pull in ancestors that sit under the floor — an app's slim launcher
        // owning fat helpers is the normal shape, and without it every helper
        // becomes its own root (VS Code / Chrome lose their family)
        var pending = table.values.map(\.ppid).filter { $0 > 1 }
        var hops = 0
        while !pending.isEmpty, hops < 25 {
            var next: [Int] = []
            for parent in Set(pending) where table[parent] == nil {
                guard let raw = ProcTable.lightweight(pid: parent) else { continue }
                table[parent] = Entry(pid: raw.pid, ppid: raw.ppid,
                                      rssMB: raw.residentMB, args: raw.command)
                if raw.ppid > 1 { next.append(raw.ppid) }
            }
            pending = next
            hops += 1
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
            let isDev = isDevTooling(e.args)
            return LiveProcess(pid: e.pid, residentMB: e.rssMB,
                               rawName: CommandLineDisplay.shown(e.args),
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
