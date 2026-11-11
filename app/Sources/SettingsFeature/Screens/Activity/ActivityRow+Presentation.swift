import AnalyzersKit
import SwiftUI
import UIComponents

/// How an Activity row looks: its glyph, its time and where it leads. The row's
/// facts come from `AnalyzersKit/Activity`; this is only how they are drawn.

extension EngineLog {
    /// The name Activity gives a log's entries. The task logs take their name
    /// from the task (`JobKind.title`); these are the event logs'.
    var activityTitle: String {
        switch self {
        case .guardLog: "Memory Guard"
        case .persistence: "Login & Startup Items — changes"
        case .forensics: "Memory Guard — crisis report"
        default: title
        }
    }
}

extension ActivityRow {

    /// The tile at the row's leading edge: what became of the run, or for an
    /// event, what kind of event it is.
    struct Glyph {
        let symbol: String
        let tone: Tokens.Tone
        let spins: Bool
        /// Attention (a waiting review, a failure) gets a stronger tint than a routine success.
        var loud = false
    }

    var glyph: Glyph {
        if isEventLog {
            switch log {
            case .forensics: return Glyph(symbol: "exclamationmark.triangle.fill", tone: Tokens.Status.destructive, spins: false, loud: true)
            case .persistence: return Glyph(symbol: "person.badge.key", tone: Tokens.Status.caution, spins: false)
            default: return Glyph(symbol: "shield.lefthalf.filled", tone: Tokens.Domain.guardLog, spins: false)
            }
        }
        if needsReview { return Glyph(symbol: "eye.fill", tone: Tokens.Status.caution, spins: false, loud: true) }
        // found something, nothing changed, and nothing the app can apply any more: its own
        // calm glyph, apart from the green check of "done" and from the orange review eye
        if status == .done, intent == .preview, findings > 0 {
            return Glyph(symbol: "magnifyingglass", tone: Tokens.Status.preview, spins: false)
        }
        switch status {
        case .running: return Glyph(symbol: "arrow.triangle.2.circlepath", tone: Tokens.Status.preview, spins: true)
        case .queued: return Glyph(symbol: "clock.fill", tone: Tokens.Status.inert, spins: false)
        case .done: return Glyph(symbol: "checkmark", tone: Tokens.Status.safe, spins: false)
        case .failed: return Glyph(symbol: "exclamationmark.triangle.fill", tone: Tokens.Status.destructive, spins: false, loud: true)
        case .stopped: return Glyph(symbol: "stop.fill", tone: Tokens.Status.inert, spins: false)
        case .none: return Glyph(symbol: kind?.symbol ?? "circle.dashed", tone: Tokens.Status.inert, spins: false)
        }
    }

    /// "Started by you", "Started by the schedule"; nil when nothing says who.
    var startedBy: String? {
        switch trigger {
        case .you: "Started by you"
        case .schedule: "Started by the schedule"
        case .guardian: isEventLog ? nil : "Started by the memory guard"
        case .terminal: "Started from Terminal"
        case .unknown: nil
        case .setup: "Started by Setup"
        case .update: "Started by an update"
        }
    }

    /// The short form beside the time: "Schedule", "You". Nil when unknown, and
    /// for the guard's own entries, whose name already says it.
    var starterShort: String? {
        switch trigger {
        case .you: "You"
        case .schedule: "Schedule"
        case .guardian: isEventLog ? nil : "Guard"
        case .terminal: "Terminal"
        case .unknown: nil
        case .setup: "Setup"
        case .update: "Update"
        }
    }

    /// Relative while it is today, the clock time under a day heading, and
    /// nothing for an entry with no time. The exact moment is `exactTime`.
    func timeText(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let started else { return "" }
        if calendar.isDate(started, inSameDayAs: now) {
            let age = now.timeIntervalSince(started)
            if age < 60 { return "Just now" }
            if age < 3600 { return "\(Int(age / 60)) min ago" }
            return started.formatted(date: .omitted, time: .shortened)
        }
        return started.formatted(date: .omitted, time: .shortened)
    }

    var exactTime: String {
        started.map { $0.formatted(date: .complete, time: .standard) } ?? "No time was recorded"
    }

    /// How long it took, once it has finished.
    var durationText: String? {
        guard let duration else { return nil }
        if duration < 1 { return "under a second" }
        return Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }

    /// Where "Open <Task>" goes: the task's own screen.
    var ownerTarget: String? {
        if let log { return "log:\(log.rawValue)" }
        switch kind {
        case .memoryReport, .storageReport: return "reports"
        case .networkSnapshot: return "network"
        case .installAgents, .sudoersInstall: return "setup"
        case .uninstallAgents: return "uninstall"
        default: return nil
        }
    }

    /// Where "Review and apply" goes: the screen that holds that task's review.
    var reviewTarget: String? {
        switch kind {
        case .memoryClean, .reclaim, .storageClean, .janitor, .tempClean: "actions:\(kind?.rawValue ?? "")"
        case .spotlight: "spotlight"
        case .loginItems: "log:loginItems"
        default: ownerTarget
        }
    }

    /// What a row leads to when it is opened: its job's screen, or the logged
    /// run's. Nil for a task that has not run.
    var route: Route? {
        if let jobID { return .job(jobID) }
        if case .logged(let log, let header, let ordinal) = source {
            return .run(RunReference(log: log, header: header, ordinal: ordinal))
        }
        return nil
    }
}
