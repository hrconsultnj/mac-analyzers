import Foundation

/// One human-readable memory-guard event parsed from guard.log. The parser
/// that turns log lines into these lives in GuardLogParser.swift.
public struct GuardEvent: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case killed(reason: String)
        /// The guard tried to stop a process and it had already ended.
        case stopFailed
        case spike(grewMB: Int)
        case warning                                        // generic fallback
        case capExceeded(killDisabled: Bool)                // over cap, kills off
        case pressureWarning(level: Int)
        case pressureCritical(level: Int, killDisabled: Bool)
        case cpuHog(pct: Int, ticks: Int)
        case forensics(path: String)
    }

    /// Filter-chip bucket for this event.
    public enum Category: String, CaseIterable, Sendable {
        case all = "All"
        case spikes = "Spikes"
        case killed = "Killed"
        case reports = "Reports"
        case pressure = "Pressure & Cap"
        case cpu = "CPU Hogs"
    }

    public var category: Category {
        switch kind {
        case .killed, .stopFailed: .killed
        case .spike: .spikes
        case .forensics: .reports
        case .cpuHog: .cpu
        case .capExceeded, .pressureWarning, .pressureCritical, .warning: .pressure
        }
    }

    public let id: String
    public let date: Date
    public let kind: Kind
    public let processName: String
    public let pid: Int?
    public let residentMB: Int?
    public let raw: String

    public init(id: String, date: Date, kind: Kind, processName: String,
                pid: Int?, residentMB: Int?, raw: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.processName = processName
        self.pid = pid
        self.residentMB = residentMB
        self.raw = raw
    }

    public var isKill: Bool { if case .killed = kind { return true }; return false }

    /// "6.1 GB" style resident-size string.
    public var residentText: String? {
        residentMB.map { String(format: "%.1f GB", Double($0) / 1024) }
    }

    /// Full human sentence for the row, without the timestamp.
    public var summary: String {
        switch kind {
        case .killed(let reason):
            return "\(processName) killed — was \(residentText ?? "?") (\(reason))"
        case .spike(let grew):
            let grewText = String(format: "%.1f GB", Double(grew) / 1024)
            return "\(processName) climbing — at \(residentText ?? "?") (+\(grewText))"
        default:
            return title
        }
    }

    /// Human name from the glossary ("Next.js dev server"), else the raw one.
    public var friendlyName: String {
        ProcessGlossary.friendlyName(for: processName) ?? processName
    }

    /// Two-line row support: TITLE = friendly what-happened,
    /// SUBTITLE = raw identity + mechanics (time appended by the view).
    public var title: String {
        switch kind {
        case .killed:
            return "\(friendlyName) killed — was \(residentText ?? "?")"
        case .spike(let grew):
            let grewText = String(format: "%.1f GB", Double(grew) / 1024)
            return "\(friendlyName) climbing — at \(residentText ?? "?") (+\(grewText))"
        case .capExceeded(let killDisabled):
            return "\(friendlyName) over the cap — \(residentText ?? "?")\(killDisabled ? " (kills off — notified only)" : "")"
        case .pressureWarning(let level):
            return "Memory pressure warning (level \(level)) — compressing/swapping"
        case .pressureCritical(let level, let killDisabled):
            return "Memory pressure critical (level \(level))\(killDisabled ? " — kills off, notified only" : "")"
        case .cpuHog(let pct, let ticks):
            return "\(friendlyName) sustained \(pct)%+ CPU for \(ticks) checks"
        case .forensics:
            return "Forensics report written"
        case .stopFailed:
            return "\(friendlyName) could not be stopped — already gone"
        case .warning:
            return processName
        }
    }

    public var subtitle: String {
        var parts: [String] = []
        switch kind {
        case .forensics(let path):
            parts.append((path as NSString).lastPathComponent)
        default:
            if friendlyName != processName { parts.append(processName) }
            if let pid { parts.append("pid \(pid)") }
            if case .killed(let reason) = kind { parts.append(reason) }
        }
        return parts.joined(separator: " · ")
    }
}
