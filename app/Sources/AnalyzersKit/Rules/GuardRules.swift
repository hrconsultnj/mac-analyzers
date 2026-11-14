import Foundation
import Synchronization

/// The person's own changes to the plan, `~/mac-analyzers/rules.local.json`, written only by the app and sparse: a mode per
/// rule, a limit or time for a rule, the two lists of programs (never close, may be asked to quit) and nothing else.
/// A field this version does not know makes the WHOLE file unused (the plan's defaults apply) and is reported, because a
/// setting that is silently dropped is worse than one that says it was.
public struct GuardLocalRules: Sendable {
    public var modes: [String: GuardRule.Mode] = [:]
    public var limits: [String: (gb: Double?, overFor: Int?)] = [:]
    /// Identities (a program's name, a bundle identifier or an executable path) never to be touched.
    public var neverClose: [String] = []
    /// Apps that may be asked to quit when memory has run out (the step "listed").
    public var mayQuit: [String] = []
    public var problems: [String] = []

    public static let empty = GuardLocalRules()

    public init(neverClose: [String] = [], mayQuit: [String] = [], problems: [String] = []) {
        self.neverClose = neverClose; self.mayQuit = mayQuit; self.problems = problems
    }

    public static func parse(_ data: Data) -> GuardLocalRules {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return GuardLocalRules(problems: ["rules.local.json is not a JSON object, so it is not used"])
        }
        var result = GuardLocalRules()
        let allowed: Set<String> = ["schema", "modes", "limits", "neverClose", "mayQuit"]
        for key in root.keys.sorted() where !allowed.contains(key) { result.problems.append("rules.local.json has a field this version does not know: \(key)") }
        if root["schema"] as? Int != 1 { result.problems.append("rules.local.json has no schema 1") }
        if let modes = root["modes"] as? [String: String] {
            for (id, text) in modes {
                if let mode = GuardRule.Mode(rawValue: text) { result.modes[id] = mode } else { result.problems.append("\(id): \(text) is not a mode") }
            }
        } else if root["modes"] != nil { result.problems.append("modes is not a list of rule and mode") }
        if let limits = root["limits"] as? [String: [String: Any]] {
            for (id, entry) in limits {
                for key in entry.keys where key != "gb" && key != "overFor" { result.problems.append("\(id): a limit has a field this version does not know: \(key)") }
                result.limits[id] = ((entry["gb"] as? NSNumber)?.doubleValue, entry["overFor"] as? Int)
            }
        } else if root["limits"] != nil { result.problems.append("limits is not a list of rule and numbers") }
        result.neverClose = (root["neverClose"] as? [String]) ?? []
        result.mayQuit = (root["mayQuit"] as? [String]) ?? []
        // a file with a problem is not used in part
        return result.problems.isEmpty ? result : GuardLocalRules(problems: result.problems)
    }
}

/// What never is touched, from `protected.json`.
public struct GuardProtected: Sendable {
    public let names: Set<String>
    public let kinds: Set<String>
    public let problems: [String]

    public static func parse(_ data: Data) -> GuardProtected {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], root["schema"] as? Int == 1 else {
            return GuardProtected(names: [], kinds: [], problems: ["protected.json is not a list of protections"])
        }
        let unknown = root.keys.filter { !["schema", "about", "names", "kinds"].contains($0) }.sorted()
        guard unknown.isEmpty else { return GuardProtected(names: [], kinds: [], problems: unknown.map { "protected.json has a field this version does not know: \($0)" }) }
        return GuardProtected(names: Set(((root["names"] as? [String]) ?? []).map { $0.lowercased() }),
                              kinds: Set((root["kinds"] as? [String]) ?? []), problems: [])
    }
}

/// A rule with the person's numbers applied, and what it is doing.
public struct ResolvedRule: Identifiable, Sendable {
    public let rule: GuardRule
    public let state: RuleState
    /// A sentence when the person asked for more than this version allows (Acting for a rule the guard script does not do).
    public let note: String?
    public var id: String { rule.id }
}

/// The rules in force: the plan, the person's changes to it, what is protected, resolved into rules with a state each.
/// Read fresh when a file changes. A plan that cannot be read leaves no rules and says why (`problems`), and the guard
/// script is untouched either way: it never reads these files.
public struct GuardRules: Sendable {
    public let plan: GuardPlan
    public let local: GuardLocalRules
    public let protected: GuardProtected
    public let catalog: KindCatalog
    public let resolved: [ResolvedRule]

    public var problems: [String] { plan.problems + local.problems + protected.problems }
    public var limits: [ResolvedRule] { resolved.filter { !$0.rule.isStep } }
    public var steps: [ResolvedRule] { resolved.filter { $0.rule.isStep } }

    /// The rules that target one kind, limits first.
    public func rules(for kind: ProcessKind) -> [ResolvedRule] { resolved.filter { $0.rule.targets(kind) } }

    public init(plan: GuardPlan, local: GuardLocalRules, protected: GuardProtected, catalog: KindCatalog) {
        self.plan = plan; self.local = local; self.protected = protected; self.catalog = catalog
        resolved = plan.rules.map { rule in
            let adjusted: GuardRule = local.limits[rule.id].map { rule.overriding(gb: $0.gb, overFor: $0.overFor) } ?? rule
            if let problem = rule.problem { return ResolvedRule(rule: adjusted, state: .cantRun(problem), note: nil) }
            let wanted = local.modes[rule.id] ?? rule.defaultMode
            switch wanted {
            case .off: return ResolvedRule(rule: adjusted, state: .off, note: nil)
            case .watching: return ResolvedRule(rule: adjusted, state: .watching, note: nil)
            case .acting:
                // Acting is only ever what the guard script already does; the app acts on nothing in this version
                return rule.defaultMode == .acting
                    ? ResolvedRule(rule: adjusted, state: .acting, note: nil)
                    : ResolvedRule(rule: adjusted, state: .watching, note: Names.Guard.actingNotYet)
            }
        }
    }

    // MARK: - loading

    private struct Source { var directory: URL? }
    private static let source = Mutex(Source())

    /// A folder to read `plan.json` and `protected.json` from, and a file for `rules.local.json`, instead of the suite's
    /// (the checkout a probe was built from, or a fixture). Test support.
    @_spi(TestSupport) public static func use(directory: URL, local: URL?) {
        source.withLock { $0.directory = directory }
        localOverride.withLock { $0 = local }
    }
    private static let localOverride = Mutex<URL?>(nil)

    private static func rulesFile(_ name: String) -> URL {
        if let directory = source.withLock({ $0.directory }) { return directory.appending(path: name) }
        let checkout = AnalyzersPaths.suiteRoot.appending(path: "memory-analyzer/rules/\(name)")
        if FileManager.default.fileExists(atPath: checkout.path) { return checkout }
        let bundled = Bundle.main.resourceURL?.appending(path: "engine/memory-analyzer/rules/\(name)")
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return checkout
    }

    /// Where the person's changes are kept.
    public static var localFile: URL {
        localOverride.withLock { $0 } ?? AnalyzersPaths.home.appending(path: "mac-analyzers/rules.local.json")
    }

    public static func load(catalog: KindCatalog = .current) -> GuardRules {
        let plan = (try? Data(contentsOf: rulesFile("plan.json"))).map { GuardPlan.parse($0, catalog: catalog) }
            ?? GuardPlan(rules: [], graceAfterLaunch: [:], alerts: [:], cooldownSeconds: 60, problems: ["plan.json was not found"])
        let protected = (try? Data(contentsOf: rulesFile("protected.json"))).map(GuardProtected.parse)
            ?? GuardProtected(names: [], kinds: [], problems: ["protected.json was not found"])
        let local = (try? Data(contentsOf: localFile)).map(GuardLocalRules.parse) ?? .empty
        return GuardRules(plan: plan, local: local, protected: protected, catalog: catalog)
    }
}
