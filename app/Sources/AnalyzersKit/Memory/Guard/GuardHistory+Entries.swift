import Foundation

/// Log events to entries: who the process was, in words, and what the guard
/// said about it.
extension GuardHistory {

    static func entries(from events: [GuardEvent]) -> [GuardEntry] {
        // the same line can appear twice in one second; the ordinal keeps ids unique
        var seen: [String: Int] = [:]
        // what a command line is called and which project it is for, worked out
        // once per distinct command: a 90-day log repeats the same few hundred
        var names: [String: (subject: String, project: String?)] = [:]
        return events.compactMap { event in
            let ordinal = seen[event.id, default: 0]
            seen[event.id] = ordinal + 1
            return entry(for: event, id: ordinal == 0 ? event.id : "\(event.id)#\(ordinal)", names: &names)
        }
    }

    private static func entry(for event: GuardEvent, id: String,
                              names: inout [String: (subject: String, project: String?)]) -> GuardEntry? {
        let named = names[event.processName] ?? (ProcessNaming.name(forCommand: event.processName),
                                                 ProcessNaming.project(inCommand: event.processName))
        names[event.processName] = named
        let (subject, project) = named
        switch event.kind {
        case .killed(let reason):
            return GuardEntry(id: id, date: event.date, kind: .stopped, subject: subject,
                              project: project, pid: event.pid, memoryMB: event.residentMB,
                              reason: GuardEntry.reasonPhrase(reason), command: event.processName, raw: event.raw)
        case .stopFailed:
            return GuardEntry(id: id, date: event.date, kind: .stopped, subject: subject,
                              project: project, pid: event.pid, stopFailed: true,
                              command: event.processName, raw: event.raw)
        case .spike(let grew):
            return GuardEntry(id: id, date: event.date, kind: .spike, subject: subject,
                              project: project, pid: event.pid, memoryMB: event.residentMB,
                              grewMB: grew, command: event.processName, raw: event.raw)
        case .capExceeded(let off):
            return GuardEntry(id: id, date: event.date, kind: .overLimit, subject: subject,
                              project: project, pid: event.pid, memoryMB: event.residentMB,
                              stoppingIsOff: off, command: event.processName, raw: event.raw)
        case .pressureWarning(let level):
            return GuardEntry(id: id, date: event.date, kind: .pressure, subject: "Memory",
                              pressureLevel: level, raw: event.raw)
        case .pressureCritical(let level, let off):
            return GuardEntry(id: id, date: event.date, kind: .pressure, subject: "Memory",
                              pressureLevel: level, stoppingIsOff: off, raw: event.raw)
        case .cpuHog(let percent, let ticks):
            return GuardEntry(id: id, date: event.date, kind: .cpu, subject: subject,
                              project: project, pid: event.pid, cpuPercent: percent,
                              cpuChecks: ticks, command: event.processName, raw: event.raw)
        case .forensics(let path):
            return GuardEntry(id: id, date: event.date, kind: .crisisReport, subject: "Memory",
                              reportPath: path.isEmpty ? nil : path, raw: event.raw)
        case .warning:
            // a free-text WARNING/CRITICAL line from an older guard: say what
            // it said rather than invent a kind for it
            return GuardEntry(id: id, date: event.date, kind: .pressure, subject: "Memory",
                              pressureLevel: 2, raw: event.raw)
        }
    }
}
