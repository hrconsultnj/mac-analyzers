import Foundation

/// Why Sparehold never quits an app by itself, asked the way the guard asks it (`ProtectionGate`): the built-in list,
/// the person's Never Close list, a Connection Tool, a live coding session inside it. Monitor reads it so the Quit confirmation
/// can say, first, why the app is normally left alone and what may be lost: the lock guards the automatic stops only, and the
/// person may still quit what they own.
///
/// "The app in front" is not asked here: while Monitor is open the app in front is Sparehold itself, so it could only ever
/// mark its own row and never the app the person was using.
public enum MonitorProtection {

    /// The answer, in the two shapes it is used in.
    public struct Note: Sendable {
        /// The reason, as the gate says it: a whole sentence ("You asked that Safari never be closed.").
        public let reason: String
        /// The reason and what it means, for the confirmation and the inspector.
        public var sentence: String { "\(reason) Sparehold never quits it by itself." }
    }

    /// The answer for an app group; nil when nothing protects it.
    public static func note(for group: CensusGroup, rules: GuardRules) -> Note? {
        let unit = RuleUnit(name: group.name, pid: group.lead.pid, members: group.members.count,
                            bytes: group.totalBytes, group: group.name, session: nil)
        guard let why = ProtectionGate.reason(group: group, unit: unit, action: .askToQuit, rules: rules,
                                              facts: RuleFacts(agentListAvailable: CodingAgentHosts.isAvailable)) else { return nil }
        return Note(reason: why)
    }
}
