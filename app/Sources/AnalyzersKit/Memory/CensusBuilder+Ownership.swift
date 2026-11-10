import Foundation

/// Which app or tool does a process belong to?
extension CensusBuilder {

    /// Shells and terminals HOST work without owning it: a dev server
    /// started from a terminal is its own story, not "part of iTerm".
    func isSessionHost(_ path: String) -> Bool {
        path.range(of: LiveStats.groupStopPattern, options: .regularExpression) != nil
    }

    /// Up the parent chain, stopping below shells and terminals — the same
    /// rule as the guard-facing family view.
    func rootAncestor(of pid: Int) -> Int {
        var current = pid
        var hops = 0
        while hops < 25,
              let entry = table[current], entry.ppid > 1,
              let parent = table[entry.ppid], !isSessionHost(parent.path) {
            current = entry.ppid
            hops += 1
        }
        return current
    }

    /// The top-level process a process answers to.
    ///
    /// Helpers macOS launches ON BEHALF of an app (web views, shader
    /// compilers, open/save panels) hang off launchd, not the app — so the
    /// parent chain alone files a browser's biggest process under "macOS".
    /// The system's own "responsible process" record says whose they are.
    func owner(of pid: Int) -> Int {
        let root = rootAncestor(of: pid)
        if let known = ownerMemo[root] { return known }
        var result = root
        if let entry = table[root], entry.ppid <= 1,
           let responsible = Responsibility.pid(for: Int32(root)).map(Int.init),
           responsible != root, responsible > 1,
           let host = table[responsible], !isSessionHost(host.path) {
            result = rootAncestor(of: responsible)
        }
        ownerMemo[root] = result
        return result
    }
}
