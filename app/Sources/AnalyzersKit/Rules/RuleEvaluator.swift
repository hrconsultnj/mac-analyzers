import Foundation

/// What the rules engine knows about the moment it looks: the clock, the memory pressure, which app is in front, and how
/// old a process is. A probe hands in its own; the app's engine reads them from the system (`live`).
public struct RuleFacts: Sendable {
    public var now: Date
    public var pressure: LiveStats.Pressure
    /// Names (lowercased) of the app in front and the ones used a moment ago: never asked to quit.
    public var frontApps: Set<String>
    /// The guard is paused (`.guard-paused`): nothing is evaluated.
    public var paused: Bool
    /// Whether the list of coding agents could be read. When it could not, nothing in Tools is judged safe.
    public var agentListAvailable: Bool
    /// Seconds since a process started, nil when it is not known.
    public var age: @Sendable (Int) -> TimeInterval?
    /// The kernel's start time of a process, for the row's identity.
    public var start: @Sendable (Int) -> Int?

    public init(now: Date = Date(), pressure: LiveStats.Pressure = .normal, frontApps: Set<String> = [], paused: Bool = false,
                agentListAvailable: Bool = true,
                age: @escaping @Sendable (Int) -> TimeInterval? = { _ in nil },
                start: @escaping @Sendable (Int) -> Int? = { _ in nil }) {
        self.now = now; self.pressure = pressure; self.frontApps = frontApps; self.paused = paused
        self.agentListAvailable = agentListAvailable; self.age = age; self.start = start
    }

    /// Read from the system now. `frontApps` is for the caller, who is on the main thread.
    public static func live(frontApps: Set<String> = []) -> RuleFacts {
        let now = Date()
        return RuleFacts(now: now, pressure: LiveStats.memoryPressure(), frontApps: frontApps,
                         paused: FileManager.default.fileExists(atPath: AnalyzersPaths.guardPauseFlag.path),
                         agentListAvailable: CodingAgentHosts.isAvailable,
                         age: { pid in ProcessIdentity.of(pid: pid).map { now.timeIntervalSince1970 - Double($0.birth.seconds) } },
                         start: { pid in ProcessIdentity.of(pid: pid).map { Int($0.birth.seconds) } })
    }
}

/// What the engine remembers between looks: since when a unit has been over a limit. Held by the one engine that looks
/// repeatedly (the app's watcher); a single look (`agent-runner --rules-once`) has none, so a rule that waits for a time
/// shows as waiting.
public struct RulesState: Sendable {
    public var overSince: [String: Date] = [:]
    /// Rows already written, so a unit is written once a day for a rule: "rule|pid|start|day".
    public var written: Set<String> = []
    public init() {}

    /// What today's file already holds: a relaunch does not write the day's rows again.
    public mutating func seed(from rows: [RuleOutcome], now: Date) {
        let day = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        for row in rows where Int(Calendar.current.startOfDay(for: row.time).timeIntervalSince1970) == day {
            written.insert(RuleOutcomes.key(rule: row.rule, result: row.result, pid: row.pid, name: row.name, start: row.startSeconds, day: day))
        }
    }
}

/// A thing a rule looks at: a process, a program (a process and what it started) or a whole app or service.
public struct RuleUnit: Sendable, Hashable {
    public let name: String
    public let pid: Int?
    public let members: Int
    public let bytes: Int64
    public let group: String
    /// Set for a program of a tools group: a live coding session started it, or runs below it.
    public let session: String?
}

public struct RuleMatch: Identifiable, Sendable {
    public enum Status: Sendable, Hashable {
        /// Over its limit for long enough: a Watching rule writes a would-have row.
        case wouldAct
        /// Over its limit, not yet for the time the rule waits (seconds left).
        case waiting(Int)
        /// A protection says no.
        case kept(String)
        /// Started too recently: a new process is never acted on.
        case tooNew
    }
    public let rule: GuardRule
    public let state: RuleState
    public let kind: ProcessKind
    public let unit: RuleUnit
    public let status: Status
    public let why: String
    public var id: String { "\(rule.id)|\(unit.group)|\(unit.pid.map(String.init) ?? "-")" }
}

public struct StepPick: Identifiable, Sendable {
    public let rule: GuardRule
    public let state: RuleState
    public let match: RuleMatch?
    /// Said when a step cannot be judged yet ("needs to know what is idle").
    public let note: String?
    public var id: String { rule.id }
}

public struct RuleEvaluation: Sendable {
    public var matches: [RuleMatch] = []
    public var picks: [StepPick] = []
    /// Rows to write now: Watching rules only, once per unit per day.
    public var outcomes: [RuleOutcome] = []
    /// Said when nothing was evaluated (paused, no rules).
    public var skipped: String?
}

/// Looks at what is running and says what each rule would do. It signals nothing and asks nothing: the only output is
/// data. In this version the guard SCRIPT is what acts (dev tooling, as always); a rule that is Acting here is one the
/// script already carries out, and the engine records nothing for it.
public enum RuleEvaluator {

    public static func evaluate(rules: GuardRules, groups: [CensusGroup], facts: RuleFacts, state: inout RulesState) -> RuleEvaluation {
        var result = RuleEvaluation()
        if facts.paused { result.skipped = "Memory Guard is paused"; return result }
        guard rules.problems.isEmpty || !rules.resolved.isEmpty else { result.skipped = rules.problems.first; return result }
        var stillOver = Set<String>()

        for resolved in rules.limits where resolved.state != .off {
            guard case .limit(let gb, let measure, let overFor, _) = resolved.rule.shape else { continue }
            if case .cantRun = resolved.state { continue }
            let limit = Int64(gb * 1_073_741_824)
            // developer tooling is judged process by process wherever it runs (what the guard script does with its pattern):
            // a vite under a shell is dev tooling though its group is "Other Commands"
            // (in a tools group: dev tooling inside an app's own bundle is the guard script's alone until rules act)
            let devProcesses = resolved.rule.selector == "tools.devTooling" && measure == .process
            for group in groups where devProcesses ? group.category == .tools : resolved.rule.targets(group.kind) {
                for unit in units(of: group, measure: measure, devOnly: devProcesses) where unit.bytes > limit {
                    let key = "\(resolved.rule.id)|\(unit.group)|\(unit.pid.map(String.init) ?? "-")"
                    stillOver.insert(key)
                    let since = state.overSince[key] ?? facts.now
                    state.overSince[key] = since
                    let status = judge(resolved: resolved, group: group, unit: unit, rules: rules, facts: facts,
                                       waited: facts.now.timeIntervalSince(since), overFor: overFor, graceKind: group.kind)
                    let why = "Using \(MemorySize.text(unit.bytes, .headline)), over the \(gbText(gb)) limit."
                    result.matches.append(RuleMatch(rule: resolved.rule, state: resolved.state, kind: group.kind, unit: unit, status: status, why: why))
                }
            }
        }
        // a unit that fell back under its limit starts again from nothing
        for key in state.overSince.keys where !stillOver.contains(key) { state.overSince[key] = nil }

        // the ladder: only walked when memory has run out; shown as "would pick now" either way
        let critical = facts.pressure == .critical
        var firstStepRecorded = false
        for resolved in rules.steps {
            if case .cantRun = resolved.state { result.picks.append(StepPick(rule: resolved.rule, state: resolved.state, match: nil, note: nil)); continue }
            guard resolved.state != .off, case .step(let which, let mb) = resolved.rule.shape else {
                result.picks.append(StepPick(rule: resolved.rule, state: resolved.state, match: nil, note: nil)); continue
            }
            if which == .idle {
                result.picks.append(StepPick(rule: resolved.rule, state: resolved.state, match: nil,
                                             note: "Needs to know what is idle, which arrives when rules start to act."))
                continue
            }
            let pick = stepPick(resolved: resolved, which: which, mb: mb, groups: groups, rules: rules, facts: facts)
            result.picks.append(StepPick(rule: resolved.rule, state: resolved.state, match: pick, note: nil))
            if critical, resolved.state == .watching, !firstStepRecorded, let pick, case .wouldAct = pick.status {
                // memory has run out: the ladder's first step with something to pick is what would have been done
                result.matches.append(pick)
                firstStepRecorded = true
            }
        }

        result.outcomes = outcomes(from: result.matches, facts: facts, state: &state)
        return result
    }

    // MARK: - units

    static func units(of group: CensusGroup, measure: GuardRule.Measure, devOnly: Bool = false) -> [RuleUnit] {
        let whole = RuleUnit(name: group.name, pid: group.lead.pid, members: group.members.count, bytes: group.totalBytes, group: group.id, session: nil)
        switch measure {
        case .unit: return [whole]
        case .process:
            return group.members.filter { !devOnly || $0.isDev }
                .map { RuleUnit(name: $0.friendlyName, pid: $0.pid, members: 1, bytes: $0.memoryBytes, group: group.id, session: nil) }
        case .program:
            guard group.category == .tools, !group.programs.isEmpty else { return [whole] }
            return group.programs.map { program in
                RuleUnit(name: program.label, pid: program.identity?.pid ?? program.members.first?.pid, members: program.members.count,
                         bytes: program.totalBytes, group: group.id,
                         session: program.lockedBy ?? (program.hostedSessions.isEmpty ? nil : "a live coding session"))
            }
        }
    }

    private static func gbText(_ gb: Double) -> String { gb == gb.rounded() ? "\(Int(gb)) GB" : String(format: "%.1f GB", gb) }

    // MARK: - protections and waiting

    private static func judge(resolved: ResolvedRule, group: CensusGroup, unit: RuleUnit, rules: GuardRules, facts: RuleFacts,
                              waited: TimeInterval, overFor: Int, graceKind: ProcessKind) -> RuleMatch.Status {
        if let reason = ProtectionGate.reason(group: group, unit: unit, action: resolved.rule.action, rules: rules, facts: facts) { return .kept(reason) }
        if let pid = unit.pid, let age = facts.age(pid), age < Double(rules.plan.grace(for: group.kind)) { return .tooNew }
        if waited < Double(overFor) { return .waiting(Int(Double(overFor) - waited)) }
        return .wouldAct
    }

    private static func stepPick(resolved: ResolvedRule, which: GuardRule.Which, mb: Int?, groups: [CensusGroup], rules: GuardRules, facts: RuleFacts) -> RuleMatch? {
        let rule = resolved.rule
        var candidates: [(CensusGroup, RuleUnit)] = []
        for group in groups where rule.selector == "tools.devTooling" ? group.category == .tools : rule.targets(group.kind) {
            switch which {
            case .listed:
                let names = Set(rules.local.mayQuit.map { $0.lowercased() })
                if names.contains(group.name.lowercased()) { candidates.append((group, units(of: group, measure: .unit)[0])) }
            default:
                // developer tooling is stopped one process at a time (what the guard script does); the rest a program or an app at a time
                let measure: GuardRule.Measure = rule.selector == "tools.devTooling" ? .process : (group.category == .tools ? .program : .unit)
                for unit in units(of: group, measure: measure, devOnly: rule.selector == "tools.devTooling") { candidates.append((group, unit)) }
            }
        }
        let floor = Int64(mb ?? 0) * 1_048_576
        let pool = candidates.filter { which == .biggestOver ? $0.1.bytes > floor : true }
            .sorted { $0.1.bytes != $1.1.bytes ? $0.1.bytes > $1.1.bytes : ($0.1.pid ?? 0) < ($1.1.pid ?? 0) }
        // the first one nothing protects
        for (group, unit) in pool {
            if let reason = ProtectionGate.reason(group: group, unit: unit, action: rule.action, rules: rules, facts: facts) { _ = reason; continue }
            if which == .listed {
                return RuleMatch(rule: rule, state: resolved.state, kind: group.kind, unit: unit, status: .wouldAct,
                                 why: "Memory had run out and you put \(group.name) on the list of apps that may be asked to quit.")
            }
            let how = which == .biggest ? "the biggest" : "the biggest over \(mb ?? 0) MB"
            return RuleMatch(rule: rule, state: resolved.state, kind: group.kind, unit: unit, status: .wouldAct,
                             why: "Memory had run out and this was \(how) of its kind: \(MemorySize.text(unit.bytes, .headline)).")
        }
        return nil
    }

    // MARK: - rows

    private static func outcomes(from matches: [RuleMatch], facts: RuleFacts, state: inout RulesState) -> [RuleOutcome] {
        var rows: [RuleOutcome] = []
        let day = Int(Calendar.current.startOfDay(for: facts.now).timeIntervalSince1970)
        // yesterday's keys are of no use to today: the set does not grow for as long as the app runs
        state.written = state.written.filter { $0.hasSuffix("|\(day)") }
        for match in matches where match.state == .watching {
            let result: String, because: String?
            switch match.status {
            case .wouldAct: result = "would"; because = nil
            case .kept(let reason): result = "kept"; because = reason
            case .waiting, .tooNew: continue
            }
            let start = match.unit.pid.flatMap(facts.start)
            let key = RuleOutcomes.key(rule: match.rule.id, result: result, pid: match.unit.pid, name: match.unit.name, start: start, day: day)
            guard state.written.insert(key).inserted else { continue }
            rows.append(RuleOutcome(ref: UUID().uuidString, time: facts.now, rule: match.rule.id, mode: "watching", result: result,
                                    category: match.kind.category.rawValue, kind: match.kind.id, name: match.unit.name,
                                    pid: match.unit.pid, startSeconds: start, members: match.unit.members, bytes: match.unit.bytes,
                                    action: match.rule.action.rawValue, why: match.why, keptBecause: because))
        }
        return rows
    }
}
