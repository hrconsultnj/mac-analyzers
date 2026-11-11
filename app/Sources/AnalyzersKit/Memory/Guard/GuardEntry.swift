import Foundation

/// One thing the memory guard did or noticed, in words: the typed form of a
/// guard.log line. The log line is the source and is kept (`event.raw`) for
/// the raw-output screen; nothing on screen is the line itself.
public struct GuardEntry: Identifiable, Hashable, Sendable {

    public enum Kind: String, Sendable, CaseIterable {
        /// The guard ended a developer tool.
        case stopped
        /// A tool grew fast between two checks (alert only).
        case spike
        /// A tool went over the memory limit.
        case overLimit
        /// The whole Mac was short of memory.
        case pressure
        /// A program kept the processor busy (alert only).
        case cpu
        /// A snapshot of every big process, written during a crisis.
        case crisisReport
    }

    public let id: String
    public let date: Date
    public let kind: Kind
    /// The app or tool, named in words ("Node.js", "Vite dev server", "Media Analysis").
    public let subject: String
    /// The project the tool is running for, when its command line says.
    public let project: String?
    public let pid: Int?
    public let memoryMB: Int?
    /// For pressure: how bad it was (2 high, 4 critical).
    public let pressureLevel: Int?
    /// The guard was told not to stop anything of this kind, so it only alerted.
    public let stoppingIsOff: Bool
    /// The guard tried to stop it and it had already ended on its own.
    public let stopFailed: Bool
    /// Why the guard stopped it, as a phrase ("over the 6 GB limit").
    public let reason: String?
    /// For a spike, how much it grew.
    public let grewMB: Int?
    /// For a CPU alert: the load and how many checks it lasted.
    public let cpuPercent: Int?
    public let cpuChecks: Int?
    /// For a crisis report: the file.
    public let reportPath: String?
    /// The process as the log named it (its command line, as far as the log kept it).
    public let command: String
    /// The log line this came from.
    public let raw: String

    public init(id: String, date: Date, kind: Kind, subject: String, project: String? = nil,
                pid: Int? = nil, memoryMB: Int? = nil, pressureLevel: Int? = nil,
                stoppingIsOff: Bool = false, stopFailed: Bool = false, reason: String? = nil, grewMB: Int? = nil,
                cpuPercent: Int? = nil, cpuChecks: Int? = nil, reportPath: String? = nil,
                command: String = "", raw: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.subject = subject
        self.project = project
        self.pid = pid
        self.memoryMB = memoryMB
        self.pressureLevel = pressureLevel
        self.stoppingIsOff = stoppingIsOff
        self.stopFailed = stopFailed
        self.reason = reason
        self.grewMB = grewMB
        self.cpuPercent = cpuPercent
        self.cpuChecks = cpuChecks
        self.reportPath = reportPath
        self.command = command
        self.raw = raw
    }

    /// Whether the process the log named is still the one running — nil when
    /// the entry has no process (pressure, a crisis report).
    public var isStillRunning: Bool? {
        guard let pid, !command.isEmpty else { return nil }
        return ProcessLiveness.isStillRunning(pid: pid, name: command, loggedAt: date)
    }

    /// "Node.js in shop-api", or the plain name.
    public var subjectWithProject: String {
        project.map { "\(subject) in \($0)" } ?? subject
    }

    public var memoryText: String? { memoryMB.map { GuardEntry.gigabytes($0) } }

    static func gigabytes(_ megabytes: Int) -> String {
        megabytes >= 1024 ? String(format: "%.1f GB", Double(megabytes) / 1024) : "\(megabytes) MB"
    }
}

// MARK: - what it says

extension GuardEntry {

    /// The row's title: what happened, to what.
    public var title: String {
        switch kind {
        case .stopped: stopFailed ? "Tried to stop \(subjectWithProject)" : "Stopped \(subjectWithProject)"
        case .spike: "\(subjectWithProject) grew to \(memoryText ?? "a large size")"
        case .overLimit: "\(subjectWithProject) went over the memory limit"
        case .pressure: pressureLevel.map { $0 >= 4 ? "Memory was critically low" : "Memory pressure was high" } ?? "Memory pressure"
        case .cpu: "\(subjectWithProject) kept the processor busy"
        case .crisisReport: "Memory crisis"
        }
    }

    /// What the guard did about it, in one sentence.
    public var outcome: String {
        switch kind {
        case .stopped:
            if stopFailed { return "It had already ended by the time the guard acted, so nothing was stopped." }
            let size = memoryText.map { "It was using \($0)" } ?? "It was using a lot of memory"
            return reason.map { "\(size), \($0)." } ?? "\(size)."
        case .spike:
            let grew = grewMB.map { "Up \(GuardEntry.gigabytes($0)) since the last check. " } ?? ""
            return grew + "Only an alert — nothing was stopped."
        case .overLimit:
            let size = memoryText.map { "It was using \($0). " } ?? ""
            return size + (stoppingIsOff
                ? "Stopping at the limit is turned off, so the guard only alerted you."
                : "The guard stopped it.")
        case .pressure:
            let critical = (pressureLevel ?? 0) >= 4
            if critical {
                return stoppingIsOff
                    ? "Stopping on critical pressure is turned off, so the guard only alerted you."
                    : "The guard looked for a developer tool to stop and wrote a crisis report."
            }
            return "The Mac was compressing memory to make room. The guard only alerted you."
        case .cpu:
            var text = "Stayed above \(cpuPercent ?? 150)% for \(cpuChecks ?? 3) checks. "
            text += "Only an alert — nothing was stopped."
            return text
        case .crisisReport:
            return "The guard wrote a report of the biggest programs at that moment."
        }
    }

    /// Why the guard does this, for the entry's own screen.
    public var why: String {
        switch kind {
        case .stopped:
            return "The guard ends a developer tool that grows past the limit you set, or that is using the most memory when the whole Mac is critically short, so one runaway cannot take everything down. It only ever stops developer tools, never your apps."
        case .spike:
            return "The guard alerts you when a developer tool's memory jumps quickly between two checks, because that is usually how a runaway begins."
        case .overLimit:
            return "The guard watches every developer tool against the memory limit you set in Settings."
        case .pressure:
            return "macOS reports how short of memory the Mac is. When it is critical the guard acts, and when it is only high the guard tells you."
        case .cpu:
            return "A program that keeps the processor busy for several checks in a row is usually stuck or doing something you should know about."
        case .crisisReport:
            return "When memory is critically low the guard saves a list of the biggest programs, so you can see afterwards what was using it."
        }
    }

    /// The phrase after "Stopped X —": "over the 6 GB limit".
    static func reasonPhrase(_ reason: String) -> String {
        reason.replacingOccurrences(of: #"\bRAM cap\b"#, with: "memory limit", options: .regularExpression)
            .replacingOccurrences(of: #"\bcap\b"#, with: "limit", options: .regularExpression)
            .replacingOccurrences(of: "critical memory pressure", with: "memory was critically low")
    }
}
