import Foundation

/// One rule of Memory Guard, as data: a limit a kind may not stay over, or a step of what to do when memory has run out.
/// The rules come from `memory-analyzer/rules/plan.json` (what ships), changed only by the person's sparse
/// `rules.local.json`; see `GuardRules`. In this version no rule acts through the app: a rule is Acting only where the
/// guard script already does the same thing today, and every other rule is Watching, which writes a "would have" row and
/// stops nothing.
public struct GuardRule: Identifiable, Sendable, Hashable {

    public enum Mode: String, Sendable, Hashable { case acting, watching, off }
    public enum Action: String, Sendable, Hashable { case stop, notify, propose, askToQuit }
    public enum Measure: String, Sendable, Hashable { case process, unit, program }
    public enum Which: String, Sendable, Hashable { case idle, biggest, biggestOver, listed }

    public enum Shape: Sendable, Hashable {
        /// Over `gb` for `overFor` seconds: what a kind may not stay over. `measure` says what is measured.
        case limit(gb: Double, measure: Measure, overFor: Int, whenBusy: Action?)
        /// One step of the ladder walked when memory has run out.
        case step(which: Which, mb: Int?)
    }

    public let id: String
    /// Which kinds it targets: an exact kind id, a category (`apps.*`), or `tools.devTooling`.
    public let selector: String
    public let shape: Shape
    public let action: Action
    /// Where the plan starts it.
    public let defaultMode: Mode
    /// The setting that holds its numbers today, when there is one (`managedBlock:GUARD_HARD_CAP_MB,…`).
    public let store: String?
    /// Why it cannot run (an unknown field, a value out of range); nil when it can. A rule that cannot run never acts and
    /// is shown as "Can't Run" with this sentence.
    public let problem: String?

    public var isStep: Bool { if case .step = shape { true } else { false } }

    /// Whether this rule targets the kind.
    public func targets(_ kind: ProcessKind) -> Bool {
        if selector == "tools.devTooling" { return kind.category == .tools && kind.devTooling }
        if selector.hasSuffix(".*") { return kind.id.hasPrefix(String(selector.dropLast(1))) }
        return kind.id == selector
    }

    /// The same rule with the person's own numbers (`rules.local.json`).
    func overriding(gb: Double?, overFor: Int?) -> GuardRule {
        guard case .limit(let planGB, let measure, let planFor, let busy) = shape else { return self }
        return GuardRule(id: id, selector: selector,
                         shape: .limit(gb: gb ?? planGB, measure: measure, overFor: overFor ?? planFor, whenBusy: busy),
                         action: action, defaultMode: defaultMode, store: store, problem: problem)
    }
}

/// What a rule is doing now.
public enum RuleState: Sendable, Hashable {
    /// The guard script does this today (the rules engine in the app never stops anything in this version).
    case acting
    /// Only writes what it would have done.
    case watching
    case off
    case cantRun(String)

    public var title: String {
        switch self {
        case .acting: Names.Guard.stateActing
        case .watching: Names.Guard.stateWatching
        case .off: Names.Guard.stateOff
        case .cantRun: Names.Guard.stateCantRun
        }
    }
}
