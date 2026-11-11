import Foundation

/// What ONE Stop on a program may signal, worked out from the live process table
/// at the moment of the stop — never from the sample the person was looking at.
///
/// A program is the process a family climbs to (the topmost ancestor below a
/// shell, terminal or launchd) and what runs under it. A stop reaches:
///  - the members the person saw, each only if it is still the process that was
///    listed (start time re-checked at every signal);
///  - descendants those members started since, because they are the program's own;
///  - NEVER an interactive shell (a shell without `-c` is a terminal session) nor
///    anything under one: that is a different program that happens to sit below it;
///  - NEVER an ancestor: the walk only goes down;
///  - NEVER anything when this process, or an ancestor of it, is in the reach;
///  - NEVER anything when any process in the reach is, sits under, or sits ABOVE a
///    live coding session, anywhere in the whole subtree (through the terminals the
///    reach does not enter too). The whole Stop is refused, naming the sessions.
enum ProgramReach {

    enum Outcome {
        /// Leaf first, each with the start time it has now (or had when listed).
        case reach([ProcessIdentity])
        case refused(String)
    }

    /// A shell is a terminal session only when it is interactive: no command (`-c`, or
    /// any flag cluster containing `c`, like `-lc`) and no script to run. `bash -lc "…"` (how
    /// an agent runs one command) and `bash memory-guard.sh` (a daemon) are not terminals.
    static func isInteractiveShell(command: String) -> Bool {
        let words = command.split(separator: " ").map(String.init)
        guard let first = words.first else { return false }
        let name = (first.split(separator: "/").last.map(String.init) ?? first).drop { $0 == "-" }
        guard CensusBuilder.shells.contains(String(name)) else { return false }
        // options that take a value of their own, which is not a script
        let takesValue: Set<String> = ["--init-file", "--rcfile", "-o", "+o", "-O", "+O"]
        var index = 1
        while index < words.count {
            let word = words[index]
            if word == "--" { return words.count - 1 == index }
            if word.hasPrefix("--") || word.hasPrefix("+") || (word.hasPrefix("-") && word.count > 1) {
                if word.hasPrefix("-"), !word.hasPrefix("--"), word.dropFirst().contains("c") { return false }
                index += takesValue.contains(word) ? 2 : 1
                continue
            }
            return false   // a script path
        }
        return true
    }

    /// "4 live Claude Code sessions", for the refusal that names what a program hosts.
    static func hostedText(_ hosted: [String: Int]) -> String {
        hosted.sorted { $0.key < $1.key }.map { agent, count in
            "\(count) live \(agent) session\(count == 1 ? "" : "s")"
        }.joined(separator: " and ")
    }

    /// This process and every ancestor of it.
    static func selfChain() -> Set<Int32> {
        var chain: Set<Int32> = []
        var current = getpid()
        while current > 1, chain.insert(current).inserted {
            current = Int32(ProcTable.parentPID(of: current))
        }
        return chain
    }

    static func compute(listed: [ProcessIdentity], name: String) -> Outcome {
        let verified = listed.filter(\.isStillRunning)
        guard !verified.isEmpty else { return .reach([]) }

        var children: [Int32: [Int32]] = [:]
        var parentOf: [Int32: Int32] = [:]
        for pid in ProcTable.allPIDs() {
            let parent = Int32(ProcTable.parentPID(of: pid))
            parentOf[pid] = parent
            children[parent, default: []].append(pid)
        }
        let listedPIDs = Set(verified.map { Int32($0.pid) })
        let roots = listedPIDs.filter { !listedPIDs.contains(parentOf[$0] ?? 0) }

        for root in roots where isInteractiveShell(command: ProcTable.commandLine(of: root)) {
            return .refused("\(name) is a terminal session. Close its window to end it.")
        }

        var depth: [Int32: Int] = [:]
        var stack: [(Int32, Int)] = roots.map { ($0, 0) }
        while let (pid, level) = stack.popLast() {
            guard depth[pid] == nil else { continue }
            // another terminal session below this program is another program
            if !roots.contains(pid), isInteractiveShell(command: ProcTable.commandLine(of: pid)) { continue }
            depth[pid] = level
            for child in children[pid] ?? [] { stack.append((child, level + 1)) }
        }

        let own = selfChain()
        if depth.keys.contains(where: own.contains) {
            return .refused("Stopping \(name) would end Mac Analyzers itself, or the program that started it, so nothing was stopped.")
        }
        // Sessions BELOW the program count too, including below the terminals the
        // reach does not enter: ending a program that hosts terminals closes them
        // and every session inside. Everything below every root is looked at.
        let hosted = CodingAgentHosts.sessionsBelow(roots: Array(roots), children: children)
        if !hosted.isEmpty {
            return .refused("\(name) hosts \(hostedText(hosted)), so nothing was stopped. Close them there.")
        }
        for pid in depth.keys {
            if let agent = CodingAgentHosts.liveSessionAgent(pid: Int(pid)) {
                return .refused("\(name) is, or holds, a live \(agent) session, so nothing was stopped. Close the session there.")
            }
        }

        let listedByPID = Dictionary(verified.map { (Int32($0.pid), $0) }, uniquingKeysWith: { first, _ in first })
        let members = depth.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .compactMap { pid, _ in listedByPID[pid] ?? ProcessIdentity.of(pid: Int(pid)) }
        return .reach(members)
    }
}
