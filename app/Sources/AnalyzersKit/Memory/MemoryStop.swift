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
        /// Why Sparehold never stops this by itself and what stopping it costs, when it is protected and the
        /// person chose the stop anyway: the confirmation says it first and the confirming button is styled as
        /// destructive. nil when nothing protects it.
        public var warning: String? = nil
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
    ///
    /// An app that runs containers or virtual machines (`appName` is on the list's `container` lines) adds
    /// that what runs inside will stop: the process table cannot see inside it, so a session there is not counted.
    public static func hostedNote(_ hosted: [String: Int], appName: String? = nil) -> String? {
        guard CodingAgentHosts.isAvailable else {
            return "Sparehold could not check whether coding sessions run inside it, so any that do will end with it."
        }
        var parts: [String] = []
        if let text = hostedText(hosted) {
            parts.append("\(text) run\(hosted.values.reduce(0, +) == 1 ? "s" : "") inside it and will end with it.")
        }
        if let appName, CodingAgentHosts.isContainerRuntime(appName: appName) {
            parts.append("Containers running in it will stop.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "2 live Claude Code sessions".
    nonisolated public static func hostedText(_ hosted: [String: Int]) -> String? {
        let parts = hosted.sorted { $0.key < $1.key }.map { agent, count in
            "\(count) live \(agent) session\(count == 1 ? "" : "s")"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " and ")
    }

    /// What quitting this app would end, read from the live process table NOW (not from the census the
    /// screen last drew): the live coding sessions inside it, and a `caution` sentence when something in it cannot
    /// be told apart yet.
    ///
    /// Quit is the person's own ⌘Q, which still asks before discarding work, so it is never refused because of
    /// what runs inside; it WARNS, and says so when it could not see what is inside (the same as when the list of
    /// coding agents is missing). A Stop, which ends a program without that ask, refuses instead.
    public static func quitReach(of identities: [ProcessIdentity], name: String) -> (hosted: [String: Int], caution: String?) {
        let reach = ProgramReach.quitReach(roots: identities.map { Int32($0.pid) })
        let caution = reach.doubt == nil ? nil
            : "Sparehold could not yet tell what is running inside it, so a coding session in it would end with it."
        return (reach.hosted, caution)
    }

    /// Plans stopping a whole group: an app is quit (⌘Q semantics); a group of
    /// tools is stopped only when it is exactly one program that may be stopped.
    public static func plan(group: CensusGroup) -> Outcome {
        let name = MonitorTree.rowName(group.name)
        switch group.quit {
        case .unavailable:
            return .refused("\(name) is part of macOS, or belongs to another account, so it cannot be stopped from here.")
        case .app(let identities):
            // the sessions inside the app are read from the live process table now, not from the census the
            // screen last drew (up to a minute old, or any age while refresh is paused)
            let reach = quitReach(of: identities, name: name)
            var detail = "\(name) will close. It will still ask before discarding unsaved work."
            if let note = hostedNote(reach.hosted, appName: name) { detail += " \(note)" }
            if let caution = reach.caution { detail += " \(caution)" }
            return .confirm(Pending(title: "Quit \(name)?", detail: detail, actionTitle: "Quit \(name)") {
                Report(GuardControl.quitApp(identities).isEmpty
                    ? "\(name) had already quit or changed, or Sparehold could not tell what it is running, so nothing was sent."
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
    ///
    /// `asPerson` is the person pressing Stop in Monitor on something they own: a lock only guards what Mac
    /// Analyzers does by itself, so a program that is part of, or hosts, a live coding session can be stopped, with
    /// the dialog saying first why it is normally left alone and what may be lost. The panel, the notifications and
    /// the guard never pass it. What a person cannot stop is the same either way: another account's, one that has gone,
    /// a terminal session, Sparehold itself.
    public static func plan(target: StopTarget, asPerson: Bool = false) -> Outcome {
        if asPerson {
            if let why = target.personRefusal { return .refused(why) }
        } else {
            if let reason = target.lockedReason { return .refused(reason) }
            guard target.canStop else { return .refused("\(target.label) belongs to another account.") }
        }
        guard target.identity != nil, !target.memberIdentities.isEmpty else {
            return .refused("\(target.label) is not running any more.")
        }
        let listed = target.memberIdentities
        let label = target.label
        let reach: [ProcessIdentity]
        switch ProgramReach.compute(listed: listed, name: label, overridingProtection: asPerson) {
        case .refused(let why): return .refused(why)
        case .reach(let found): reach = found
        }
        let started = reach.count - 1
        let what = started <= 0
            ? "\(label) will be asked to stop."
            : "\(label) and \(started) \(started == 1 ? "process" : "processes") it started will be asked to stop."
        let seconds = Int(GuardControl.defaultGrace.components.seconds)
        // what protects it is read from the live process table now, not from the census the screen last drew
        let warning = asPerson ? target.protection ?? protectionSentence(
            label: label, hosted: ProgramReach.sessionsReached(listed: reach), listAvailable: CodingAgentHosts.isAvailable) : nil
        // how many sessions the confirmation knew of: one that appears while the person decides is not covered by it
        let knownSessions = asPerson ? ProgramReach.sessionsReached(listed: listed).values.reduce(0, +) : 0
        let detail = (warning.map { "\($0) " } ?? "") + "\(what) Anything in progress is interrupted. If anything is still running after \(seconds) seconds, nothing is forced: you will be told what is left and can choose Force Stop."
        return .confirm(Pending(
            title: "Stop \(label)?", detail: detail, actionTitle: "Stop \(label)", warning: warning) {
                if asPerson, ProgramReach.sessionsReached(listed: listed).values.reduce(0, +) > knownSessions {
                    return Report("A live coding session started in \(label) while you were deciding, so nothing was stopped. Press Stop again to see what it would end.")
                }
                let result = await GuardControl.askProgramToStop(listed, name: label, overridingProtection: asPerson)
                return programReport(label, result, overridingProtection: asPerson, warning: warning)
            })
    }

    /// Why Sparehold never stops something by itself, and what stopping it would cost, in one sentence for a
    /// confirmation or a tooltip; nil when nothing protects it. `agent` is the coding agent whose live session it is
    /// part of, `hosted` the live sessions that run below it, and without the list of coding agents nothing can be told apart.
    nonisolated public static func protectionSentence(label: String, agent: String? = nil, hosted: [String: Int] = [:],
                                          listAvailable: Bool = true) -> String? {
        var parts: [String] = []
        if let agent {
            parts.append("\(label) is part of a live \(agent) session, which Sparehold never stops by itself. Stopping it can end the session and lose work in it that is not saved.")
        }
        if let text = hostedText(hosted) {
            parts.append("\(label) \(agent == nil ? "is, or hosts," : "also hosts") \(text), which Sparehold never stops by itself. Stopping it ends them too, and anything in them that is not saved is lost.")
        }
        if !listAvailable {
            parts.append("Sparehold could not read its list of coding agents, so it cannot tell whether a live coding session is part of this. Any that is will end with it.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The same for one process a person is about to stop, read from the live process table now.
    public static func protectionText(ofProcess process: LiveProcess) -> String? {
        guard let identity = process.identity ?? ProcessIdentity.of(pid: process.pid) else { return nil }
        let hosted = ProgramReach.sessionsReached(listed: [identity])
        return protectionSentence(label: process.friendlyName, hosted: hosted, listAvailable: CodingAgentHosts.isAvailable)
    }

    /// What stopping this program would reach, worked out now from the live process table: "and 6 processes
    /// it started" (nothing when it started none), or the reason a stop would be refused. Shown wherever a program is
    /// offered for a stop before the person confirms.
    public static func reachText(of target: StopTarget, asPerson: Bool = false) -> String? {
        switch ProgramReach.compute(listed: target.memberIdentities, name: target.label, overridingProtection: asPerson) {
        case .refused(let why): return why
        case .reach(let found):
            let started = found.count - 1
            return started <= 0 ? nil : "and \(started) \(started == 1 ? "process" : "processes") it started"
        }
    }

    /// The sentence after a program stop, and the Force Stop offer when something is left.
    static func programReport(_ label: String, _ result: GuardControl.ProgramStop,
                              overridingProtection: Bool = false, warning: String? = nil) -> Report {
        if let why = result.refusal { return Report(why) }
        if result.allEnded { return Report("\(label) stopped.") }
        let left = result.stillRunning
        return Report(programSummary(label, result), force: forceOffer(label, left, overridingProtection: overridingProtection, warning: warning))
    }

    /// Step two, offered only when something did not stop.
    public static func forceOffer(_ label: String, _ left: [ProcessIdentity], overridingProtection: Bool = false,
                                  warning: String? = nil) -> Pending {
        let names = left.map { identity -> String in
            let name = LiveStats.process(pid: identity.pid)?.friendlyName ?? "a process"
            return "\(name) (process \(identity.pid))"
        }
        let shown = names.prefix(8).joined(separator: ", ") + (names.count > 8 ? ", and \(names.count - 8) more" : "")
        return Pending(
            title: "Force \(label) to Stop?",
            detail: (warning.map { "\($0) " } ?? "") + "Still running: \(shown). Forcing them to stop takes effect at once. They cannot save or shut down cleanly, and a database or container may lose data. Only continue if that is acceptable.",
            actionTitle: "Force Stop", warning: warning) {
                let result = await GuardControl.forceStopProgram(left, name: label, overridingProtection: overridingProtection)
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
