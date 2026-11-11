import Foundation

/// The one way to stop or quit something from anywhere in the app — Monitor,
/// the menu-bar panel, a notification action. It applies the rules in one place:
/// a program that belongs to a live coding-agent session is never stopped, a
/// group of several separate programs is never stopped as a whole (the person
/// chooses which), and every process is re-checked against the start time it
/// was seen with before anything is sent. It never throws and never stays
/// silent: the answer says what was done, or why not, in words.
@MainActor
public enum MemoryStop {

    /// A stop that is ready and waits for the person to confirm it. Nothing has
    /// been sent yet: `run` sends it.
    public struct Pending: Sendable {
        public let title: String
        public let detail: String
        public let actionTitle: String
        public let run: @MainActor @Sendable () async -> Report
    }

    /// What a confirmed stop did, in a sentence. When something did not stop, `force` is the
    /// second, separate step (Force Stop), with its own confirmation: nothing is ever
    /// forced without it.
    public struct Report: Sendable {
        public let message: String
        public let force: Pending?
        public init(_ message: String, force: Pending? = nil) { self.message = message; self.force = force }
    }

    public enum Outcome: Sendable {
        /// Ready to do; the caller confirms with the person, then calls `run`.
        case confirm(Pending)
        /// Nothing was done, and why.
        case refused(String)
        /// More than one separate program: the caller opens Monitor at the
        /// group, where a sheet lists them with a tick each. `link` is the
        /// deep link that selects it.
        case needsChoice(reason: String, link: String)

        public var message: String {
            switch self {
            case .confirm(let pending): pending.detail
            case .refused(let reason): reason
            case .needsChoice(let reason, _): reason
            }
        }
    }

    /// The deep link that opens Monitor with a group selected, by its exact name.
    public static func monitorLink(forGroup name: String) -> String { "monitor:select:\(name)" }

    /// The sentence for a dialog that quits an app: which live coding sessions run
    /// inside it and end with it, or, when the list is unavailable, that it could not check.
    public static func hostedNote(_ hosted: [String: Int]) -> String? {
        guard CodingAgentHosts.isAvailable else {
            return "Mac Analyzers could not check whether coding sessions run inside it, so any that do will end with it."
        }
        guard let text = hostedText(hosted) else { return nil }
        return "\(text) run\(hosted.values.reduce(0, +) == 1 ? "s" : "") inside it and will end with it."
    }

    /// "2 live Claude Code sessions".
    public static func hostedText(_ hosted: [String: Int]) -> String? {
        let parts = hosted.sorted { $0.key < $1.key }.map { agent, count in
            "\(count) live \(agent) session\(count == 1 ? "" : "s")"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " and ")
    }

    /// Plans stopping a whole group: an app is quit (⌘Q semantics); a group of
    /// tools is stopped only when it is exactly one program that may be stopped.
    public static func plan(group: CensusGroup) -> Outcome {
        let name = MonitorTree.rowName(group.name)
        switch group.quit {
        case .unavailable:
            return .refused("\(name) is part of macOS, or belongs to another account, so it cannot be stopped from here.")
        case .app(let identities):
            var detail = "\(name) will close. It will still ask before discarding unsaved work."
            if let note = hostedNote(group.hostedSessions) { detail += " \(note)" }
            return .confirm(Pending(title: "Quit \(name)?", detail: detail, actionTitle: "Quit \(name)") {
                Report(GuardControl.quitApp(identities).isEmpty
                    ? "\(name) had already quit or changed, so nothing was sent."
                    : "Asked \(name) to quit.")
            })
        case .tools:
            guard CodingAgentHosts.isAvailable else { return .refused(CodingAgentHosts.unavailableSentence) }
            let stoppable = group.programs.filter(\.isStoppable)
            let locked = group.programs.filter { $0.lockedBy != nil || !$0.hostedSessions.isEmpty }
            if stoppable.isEmpty {
                if let agent = locked.first?.lockedBy {
                    return .refused(name == agent
                        ? "These are live \(agent) sessions — close them in \(agent)."
                        : "\(name) is part of a live \(agent) session — close it there.")
                }
                if let reason = group.programs.compactMap(\.lockedReason).first { return .refused(reason) }
                return .refused("None of the \(name) programs can be stopped from here.")
            }
            if group.programs.count > 1 {
                let reason = "\(name) is \(group.programs.count) separate programs"
                    + (locked.isEmpty ? "." : ", \(locked.count) of them part of a live coding session.")
                    + " Choose which to stop in Monitor."
                return .needsChoice(reason: reason, link: monitorLink(forGroup: name))
            }
            return plan(target: stoppable[0])
        }
    }

    /// Plans stopping one separate program and everything it started. The reach is
    /// computed now, from the live process table, and the dialog says its true size.
    public static func plan(target: StopTarget) -> Outcome {
        if let reason = target.lockedReason { return .refused(reason) }
        guard target.canStop else { return .refused("\(target.label) belongs to another account.") }
        guard target.identity != nil, !target.memberIdentities.isEmpty else {
            return .refused("\(target.label) is not running any more.")
        }
        let listed = target.memberIdentities
        let label = target.label
        let reach: [ProcessIdentity]
        switch ProgramReach.compute(listed: listed, name: label) {
        case .refused(let why): return .refused(why)
        case .reach(let found): reach = found
        }
        let started = reach.count - 1
        let what = started <= 0
            ? "\(label) will be asked to stop."
            : "\(label) and \(started) \(started == 1 ? "process" : "processes") it started will be asked to stop."
        let seconds = Int(GuardControl.defaultGrace.components.seconds)
        return .confirm(Pending(
            title: "Stop \(label)?",
            detail: "\(what) Anything in progress is interrupted. If anything is still running after \(seconds) seconds, nothing is forced: you will be told what is left and can choose Force Stop.",
            actionTitle: "Stop \(label)") {
                let result = await GuardControl.askProgramToStop(listed, name: label)
                return programReport(label, result)
            })
    }

    /// The sentence after a program stop, and the Force Stop offer when something is left.
    static func programReport(_ label: String, _ result: GuardControl.ProgramStop) -> Report {
        if let why = result.refusal { return Report(why) }
        if result.allEnded { return Report("\(label) stopped.") }
        let left = result.stillRunning
        return Report(programSummary(label, result), force: forceOffer(label, left))
    }

    /// Step two, offered only when something did not stop.
    public static func forceOffer(_ label: String, _ left: [ProcessIdentity]) -> Pending {
        let names = left.map { identity -> String in
            let name = LiveStats.process(pid: identity.pid)?.friendlyName ?? "a process"
            return "\(name) (process \(identity.pid))"
        }
        let shown = names.prefix(8).joined(separator: ", ") + (names.count > 8 ? ", and \(names.count - 8) more" : "")
        return Pending(
            title: "Force \(label) to Stop?",
            detail: "Still running: \(shown). Forcing them to stop takes effect at once. They cannot save or shut down cleanly, and a database or container may lose data. Only continue if that is acceptable.",
            actionTitle: "Force Stop") {
                let result = await GuardControl.forceStopProgram(left, name: label)
                if let why = result.refusal { return Report(why) }
                return Report(result.allEnded ? "\(label) was forced to stop."
                    : "\(result.stillRunning.count) of \(result.asked) processes are still running after being forced. They may belong to another account.")
            }
    }

    /// The sentence after a program stop: what ended and, honestly, what did not.
    public static func programSummary(_ label: String, _ result: GuardControl.ProgramStop) -> String {
        if let why = result.refusal {
            return result.stillRunning.isEmpty ? why : "\(label) was asked to stop, but \(result.stillRunning.count) of its \(result.asked) process\(result.asked == 1 ? " is" : "es are") still running. \(why)"
        }
        if result.allEnded { return "\(label) stopped." }
        let left = result.stillRunning.count
        return "\(label) was asked to stop, but \(left) of its \(result.asked) process\(result.asked == 1 ? " is" : "es are") still running."
    }
}
