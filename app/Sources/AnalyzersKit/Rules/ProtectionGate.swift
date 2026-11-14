import Foundation

/// Whether anything protects a unit from a rule: asked before a would-have row is written (and, when rules act, before a
/// signal). The rule data cannot remove any of these. The answer is the sentence a person reads, or nil.
///
/// Decided here: the built-in never list, the person's Never Close list, a live coding session and everything below it
/// (and, when the list of agents cannot be read, everything in Tools), an app in front, an action that needs a signal on
/// something no app may signal, and another account's process. Decided when a signal is sent, not by this engine: the
/// pid and start time are checked again at the moment of the signal, and a command line that cannot be trusted yet waits.
public enum ProtectionGate {

    public static func reason(group: CensusGroup, unit: RuleUnit, action: GuardRule.Action, rules: GuardRules, facts: RuleFacts) -> String? {
        let name = group.name.lowercased()
        // 1. what is never touched, whatever a rule says
        if rules.protected.kinds.contains(group.kind.id) { return group.kind.leftAlone ?? "\(group.kind.name) are never touched." }
        if rules.protected.names.contains(name) || rules.protected.names.contains(unit.name.lowercased()) {
            return "\(group.name) is on the list of what is never touched."
        }
        // 2. the person's own list
        let never = rules.local.neverClose.map { $0.lowercased() }
        if never.contains(name) || never.contains(unit.name.lowercased()) || never.contains(where: { $0.hasPrefix("/") && group.lead.rawName.lowercased().hasPrefix($0) }) {
            return "You asked that \(group.name) never be closed."
        }
        // 3. a live coding session, and everything below it
        if group.category == .tools {
            if !facts.agentListAvailable { return CodingAgentHosts.unavailableSentence }
            if let session = unit.session { return "Part of a live coding session (\(session)) or holding one." }
        }
        if !group.hostedSessions.isEmpty { return "A live coding session runs inside \(group.name)." }
        // 4. in use right now
        if facts.frontApps.contains(name) { return "\(group.name) is the app in front." }
        // 5. a rule that would signal something no app may signal
        let signals = action == .stop || action == .askToQuit
        if signals, group.kind.stopsWith == .none { return group.kind.leftAlone ?? "\(group.name) is never stopped." }
        if signals, let held = group.leftAlone, held.hasPrefix("Runs under another account") { return held }
        return nil
    }
}
