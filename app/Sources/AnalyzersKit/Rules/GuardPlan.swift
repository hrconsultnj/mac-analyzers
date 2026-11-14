import Foundation

/// `memory-analyzer/rules/plan.json` read and checked. A rule with a field this version does not know, a value out of its
/// range, or a selector that targets no kind, is kept with its `problem` and can't run; the rest of the plan still works.
/// A file that is not a plan at all (not JSON, schema other than 1) has no rules and says why in `problems`.
public struct GuardPlan: Sendable {
    public let rules: [GuardRule]
    public let graceAfterLaunch: [String: Int]
    public let alerts: [String: Int]
    public let cooldownSeconds: Int
    /// What is wrong with the file as a whole (nothing runs when this is not empty).
    public let problems: [String]

    public var limits: [GuardRule] { rules.filter { !$0.isStep } }
    /// The ladder, in the order the plan lists it.
    public var steps: [GuardRule] { rules.filter(\.isStep) }

    public static let empty = GuardPlan(rules: [], graceAfterLaunch: [:], alerts: [:], cooldownSeconds: 60, problems: ["no plan"])

    /// Seconds a process younger than this is never acted on, for the kind.
    public func grace(for kind: ProcessKind) -> Int {
        if kind.devTooling, let value = graceAfterLaunch["tools.devTooling"] { return value }
        return graceAfterLaunch[kind.id] ?? graceAfterLaunch["*"] ?? 0
    }

    static let limitKeys: Set<String> = ["id", "kind", "gb", "measure", "overFor", "action", "whenBusy", "mode", "store"]
    static let stepKeys: Set<String> = ["id", "kind", "which", "mb", "action", "mode", "store"]

    public static func parse(_ data: Data, catalog: KindCatalog) -> GuardPlan {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return GuardPlan(rules: [], graceAfterLaunch: [:], alerts: [:], cooldownSeconds: 60, problems: ["not a JSON object"])
        }
        var problems: [String] = []
        let allowed: Set<String> = ["schema", "about", "limits", "graceAfterLaunch", "whenMemoryRunsOut", "alerts", "cooldownSeconds"]
        for key in root.keys.sorted() where !allowed.contains(key) { problems.append("unknown field \(key)") }
        if root["schema"] as? Int != 1 { problems.append("schema is not 1") }
        guard problems.isEmpty else {
            return GuardPlan(rules: [], graceAfterLaunch: [:], alerts: [:], cooldownSeconds: 60, problems: problems)
        }
        var rules: [GuardRule] = []
        for item in (root["limits"] as? [[String: Any]]) ?? [] { rules.append(rule(item, step: false, catalog: catalog)) }
        for item in (root["whenMemoryRunsOut"] as? [[String: Any]]) ?? [] { rules.append(rule(item, step: true, catalog: catalog)) }
        var seen = Set<String>()
        rules = rules.map { rule in
            guard seen.insert(rule.id).inserted else { return rule.failing("another rule has the id \(rule.id)") }
            return rule
        }
        return GuardPlan(rules: rules,
                         graceAfterLaunch: (root["graceAfterLaunch"] as? [String: Int]) ?? [:],
                         alerts: (root["alerts"] as? [String: Int]) ?? [:],
                         cooldownSeconds: root["cooldownSeconds"] as? Int ?? 60, problems: [])
    }

    private static func rule(_ item: [String: Any], step: Bool, catalog: KindCatalog) -> GuardRule {
        let id = item["id"] as? String ?? "(no id)"
        let selector = item["kind"] as? String ?? ""
        func broken(_ why: String) -> GuardRule {
            GuardRule(id: id, selector: selector, shape: step ? .step(which: .biggest, mb: nil)
                                                              : .limit(gb: 0, measure: .unit, overFor: 0, whenBusy: nil),
                      action: .notify, defaultMode: .watching, store: nil, problem: why)
        }
        let unknown = item.keys.filter { !(step ? stepKeys : limitKeys).contains($0) }.sorted()
        if let first = unknown.first { return broken("it has a field this version does not know: \(first)") }
        guard let action = (item["action"] as? String).flatMap(GuardRule.Action.init(rawValue:)) else { return broken("its action is not one it knows") }
        guard let mode = (item["mode"] as? String).flatMap(GuardRule.Mode.init(rawValue:)) else { return broken("its mode is not one it knows") }
        let probe = GuardRule(id: id, selector: selector, shape: .step(which: .biggest, mb: nil), action: action, defaultMode: mode, store: nil, problem: nil)
        guard catalog.kinds.contains(where: { probe.targets($0) }) else { return broken("it targets no kind: \(selector)") }
        let shape: GuardRule.Shape
        if step {
            guard let which = (item["which"] as? String).flatMap(GuardRule.Which.init(rawValue:)) else { return broken("its step is not one it knows") }
            let mb = item["mb"] as? Int
            if which == .biggestOver, (mb ?? 0) <= 0 { return broken("biggestOver needs a size in mb") }
            shape = .step(which: which, mb: mb)
        } else {
            guard let gb = (item["gb"] as? NSNumber)?.doubleValue, gb > 0 else { return broken("its limit is not a size above zero") }
            guard let measure = (item["measure"] as? String).flatMap(GuardRule.Measure.init(rawValue:)) else { return broken("its measure is not one it knows") }
            guard let overFor = item["overFor"] as? Int, overFor >= 0 else { return broken("overFor is not a number of seconds") }
            shape = .limit(gb: gb, measure: measure, overFor: overFor, whenBusy: (item["whenBusy"] as? String).flatMap(GuardRule.Action.init(rawValue:)))
        }
        return GuardRule(id: id, selector: selector, shape: shape, action: action, defaultMode: mode, store: item["store"] as? String, problem: nil)
    }
}

extension GuardRule {
    func failing(_ why: String) -> GuardRule {
        GuardRule(id: id, selector: selector, shape: shape, action: action, defaultMode: defaultMode, store: store, problem: why)
    }
}
