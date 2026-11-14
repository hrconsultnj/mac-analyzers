import SwiftUI
import AnalyzersKit

/// What the rules tabs of Memory Guard show: the rules in force, what each matches right now, the would-have rows of the last
/// seven days, and the person's changes to the rules. A look at the running processes is one census (about a second), taken
/// off the main thread by the one rules engine; nothing here writes a would-have row, only the engine's own watcher does.
@MainActor @Observable
final class GuardRulesModel {
    private(set) var look: RulesLook?
    private(set) var outcomes: [RuleOutcome] = []
    private(set) var loading = false
    /// A change that was refused, with the reason (a file that cannot be read is never overwritten).
    var notice: String?
    /// The row selected in the Apps, Tools or macOS table: the inspector (the screen's) shows it.
    var selection: Set<String> = []

    var rules: GuardRules { look?.rules ?? GuardRules.load() }
    var evaluation: RuleEvaluation? { look?.evaluation }
    var groups: [CensusGroup] { look?.groups ?? [] }

    func refresh() async {
        loading = true
        let result = await RulesEngine.shared.look(frontApps: RulesEngine.frontAppNames(), write: false)
        look = result
        outcomes = RuleOutcomes.read(since: Date().addingTimeInterval(-7 * 86_400))
        loading = false
    }

    // MARK: - what a tab asks

    /// The groups running of one kind.
    func running(_ kind: ProcessKind) -> [CensusGroup] { groups.filter { $0.kind == kind } }

    func matches(rule: String, kind: ProcessKind? = nil) -> [RuleMatch] {
        (evaluation?.matches ?? []).filter { $0.rule.id == rule && (kind == nil || $0.kind == kind) }
    }

    /// A rule's would-have and kept rows of the last seven days, for one kind when a kind is asked for.
    func counts(rule: String, kind: ProcessKind? = nil) -> (would: Int, kept: Int) {
        RuleOutcomes.counts(kind.map { kind in outcomes.filter { $0.kind == kind.id } } ?? outcomes, rule: rule)
    }

    /// Would-have rows of the last seven days for a category tab's badge.
    func weekCount(_ category: CensusGroup.Category) -> Int { outcomes.filter { $0.category == category.rawValue && $0.isWould }.count }

    // MARK: - the person's changes

    func setOff(_ rule: String, _ off: Bool) {
        change { local in
            // a mode that equals the plan's is not stored: the file stays sparse
            if off { local.modes[rule] = .off } else { local.modes[rule] = nil }
        }
    }

    func add(_ list: Names.GuardList, _ name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        change { local in
            switch list {
            case .neverClose: if !local.neverClose.contains(clean) { local.neverClose.append(clean) }
            case .mayQuit: if !local.mayQuit.contains(clean) { local.mayQuit.append(clean) }
            }
        }
    }

    func remove(_ list: Names.GuardList, _ name: String) {
        change { local in
            switch list {
            case .neverClose: local.neverClose.removeAll { $0 == name }
            case .mayQuit: local.mayQuit.removeAll { $0 == name }
            }
        }
    }

    private func change(_ edit: (inout GuardLocalRules) -> Void) {
        switch GuardLocalWriter.update(edit) {
        case .success: notice = nil; GuardLocalWriter.refreshFallback(); Task { await refresh() }
        case .failure(.unreadable(let why)): notice = "Your changes were not saved: \(why)."
        }
    }
}

extension Names {
    /// The two lists the person keeps.
    enum GuardList { case neverClose, mayQuit }
}
