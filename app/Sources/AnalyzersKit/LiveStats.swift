import Foundation

/// Live system facts the menu reads on open — the same signals the guard
/// watches, so what you see is what the guard decides on.
public struct LiveProcess: Identifiable, Sendable, Hashable {
    public let pid: Int
    public let residentMB: Int
    public let rawName: String
    public var id: Int { pid }

    public var friendlyName: String { ProcessGlossary.friendlyName(for: rawName) ?? rawName }
    public var residentText: String { String(format: "%.1f GB", Double(residentMB) / 1024) }
}

public enum LiveStats {

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

    /// Biggest dev processes RIGHT NOW, by resident RAM. What you'd want to
    /// see before deciding whether to pause the guard or raise the cap.
    public static func topDevProcesses(limit: Int = 3) -> [LiveProcess] {
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
            let args = String(fields[2])
            guard args.range(of: killablePattern, options: .regularExpression) != nil else { continue }
            result.append(LiveProcess(pid: pid, residentMB: rssKB / 1024,
                                      rawName: String(args.prefix(80))))
        }
        return Array(result.sorted { $0.residentMB > $1.residentMB }.prefix(limit))
    }
}
