import Foundation

/// What the rules engine would offer to stop, for the one rule the guard script already carries out: developer tooling,
/// one process at a time. `agent-runner --compare-legacy` sets this against the script's own choice on the same process
/// table. The engine's set must be INSIDE the script's: the engine may leave something the script would stop (it does not
/// look inside an app's bundle yet), never take something the script would not.
public enum LegacyParity {

    /// Every developer-tooling process in a tools group that nothing protects, with its size: the engine's candidates.
    public static func engineCandidates(rules: GuardRules, groups: [CensusGroup], facts: RuleFacts) -> [(pid: Int, bytes: Int64, name: String)] {
        var found: [(pid: Int, bytes: Int64, name: String)] = []
        for group in groups where group.category == .tools {
            for unit in RuleEvaluator.units(of: group, measure: .process, devOnly: true) where (unit.pid ?? 0) > 500 {
                let session = group.programs.first { program in program.members.contains { $0.pid == unit.pid } }
                    .flatMap { $0.lockedBy ?? ($0.hostedSessions.isEmpty ? nil : "a live coding session") }
                let withSession = RuleUnit(name: unit.name, pid: unit.pid, members: 1, bytes: unit.bytes, group: group.id, session: session)
                if ProtectionGate.reason(group: group, unit: withSession, action: .stop, rules: rules, facts: facts) == nil, let pid = unit.pid {
                    found.append((pid, unit.bytes, unit.name))
                }
            }
        }
        return found
    }

    /// What the script does with a set of candidates (largest resident first): at the hard cap, the biggest one over the cap;
    /// at critical pressure, the biggest one over 500 MB. nil when there is none. Sizes in bytes.
    public static func victim(of candidates: [(pid: Int, bytes: Int64)], over floor: Int64) -> Int? {
        candidates.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.pid < $1.pid }
            .first { $0.bytes > floor }?.pid
    }
}

extension CensusGroup {
    /// Test support: a group built by hand for a probe: members are (pid, name, command, bytes). The first is the lead; the kind
    /// is the one the catalog gives its command, in the category named.
    @_spi(TestSupport) public static func fixture(name: String, category: Category, kind kindID: String? = nil,
                                                  members: [(pid: Int, name: String, command: String, bytes: Int64)],
                                                  lockedBy: String? = nil, hostedSessions: [String: Int] = [:],
                                                  leftAlone: String? = nil) -> CensusGroup {
        let catalog = KindCatalog.current
        let processes = members.map { member in
            LiveProcess(pid: member.pid, residentMB: Int(member.bytes / 1_048_576), rawName: member.command,
                        kind: catalog.isDevTooling(command: member.command) ? .devTool : .app,
                        footprintBytes: member.bytes, label: member.name)
        }
        let lead = processes.max { $0.memoryBytes < $1.memoryBytes } ?? processes[0]
        // a program a live coding session started: one StopTarget over every member, locked by the agent
        let programs = lockedBy.map { agent in
            [StopTarget(id: "fixture-\(lead.pid)", identity: nil, name: name, whereItRuns: nil, lockedBy: agent, canStop: true,
                        members: processes, memberIdentities: [], isInteractiveShell: false, hostedSessions: [:])]
        } ?? []
        let match: KindMatch
        if let kindID, let kind = catalog.kind(id: kindID) {
            match = KindMatch(kind: kind, basis: .identity, rule: "fixture")
        } else {
            match = catalog.recognize(ProcessSubject(path: lead.rawName.split(separator: " ").first.map(String.init) ?? lead.rawName,
                                                     command: lead.rawName, uid: 501, me: 501, appName: category == .apps ? name : nil),
                                      in: category)
        }
        return CensusGroup(id: "\(category.rawValue)/\(name.lowercased())", name: name, category: category, role: nil, lead: lead,
                           members: processes, parts: [], quit: .unavailable, programs: programs, hostedSessions: hostedSessions,
                           kind: match.kind, kindMatch: match, leftAlone: leftAlone ?? match.kind.leftAlone)
    }
}
