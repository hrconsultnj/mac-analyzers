import Foundation

/// What kind of thing is a process, and what should it be called?
extension CensusBuilder {

    /// Full command line, for the user's own non-system processes only —
    /// argv is the one costly read, so it is skipped where it can't matter.
    func argv(_ entry: Entry) -> String? {
        guard entry.uid == me,
              !entry.path.hasPrefix("/System/"), !entry.path.hasPrefix("/usr/libexec/")
        else { return nil }
        if let known = argvMemo[entry.pid] { return known }
        let value = ProcTable.commandLine(of: Int32(entry.pid))
        argvMemo[entry.pid] = value
        return value
    }

    /// The process's own name: "Opera Helper (Renderer)", "distnoted".
    func leafName(_ entry: Entry) -> String {
        if entry.path.hasPrefix("pid ") {   // path unreadable — kernel's short name
            return ProcessLiveness.commandName(pid: entry.pid) ?? "Unnamed process"
        }
        let base = (entry.path as NSString).lastPathComponent
        // a binary stored under its version number is named for a release,
        // not a program — argv[0] carries the real name
        if base.range(of: #"^[0-9][0-9.]*$"#, options: .regularExpression) != nil,
           let first = argv(entry)?.split(separator: " ").first,
           let name = first.split(separator: "/").last {
            return String(name)
        }
        return base
    }

    /// The row model for one process. `category` decides whether Quit may be
    /// offered (see `LiveProcess.canQuit`).
    func liveProcess(_ entry: Entry, label: String? = nil,
                     category: CensusGroup.Category? = nil) -> LiveProcess {
        let command = argv(entry)
        let isDev = command.map(LiveStats.isDevKillable) ?? false
        return LiveProcess(
            pid: entry.pid, residentMB: entry.residentMB,
            rawName: String((command ?? entry.path).prefix(100)),
            kind: isDev ? .devTool : .app, ppid: entry.ppid,
            footprintBytes: entry.bytes,
            label: isDev ? nil : (label ?? leafName(entry)),
            canQuit: entry.uid == me && category != .system)
    }

    /// Which of the three kinds of owner a top-level process is, and the
    /// name its group goes by.
    func classify(_ root: Entry) -> (category: CensusGroup.Category, name: String) {
        if let known = classMemo[root.pid] { return known }
        let result = uncachedClassify(root)
        classMemo[root.pid] = result
        return result
    }

    private func uncachedClassify(_ root: Entry) -> (category: CensusGroup.Category, name: String) {
        let launchedFromSession = root.ppid > 1
            && table[root.ppid].map { isSessionHost($0.path) } == true
        // Chromium browsers run their main binary from a signed temp clone
        // ("…/Opera.app.bundle/…"), so the executable path alone loses the
        // app — argv[0] still names the real bundle
        if let app = Self.outermostApp(in: root.path)
            ?? argv(root).flatMap(Self.outermostApp(in:)) {
            // Finder, Dock, Control Center… ship as .app but ARE the system
            let builtIn = ["/System/Library/", "/Library/Apple/", "/usr/"]
                .contains { app.path.hasPrefix($0) }
            return (builtIn ? .system : .apps, app.name)
        }
        if launchedFromSession {
            return (.tools, liveProcess(root).friendlyName)
        }
        if MemoryCensus.isSystemPath(root.path) || (root.path.hasPrefix("pid ") && root.uid != me) {
            return (.system, leafName(root))
        }
        return (.tools, liveProcess(root).friendlyName)
    }

    /// The OUTERMOST bundle in a path — a helper nested four frameworks deep
    /// inside Opera.app still belongs to Opera.
    static func outermostApp(in path: String) -> (path: String, name: String)? {
        guard let range = path.range(of: ".app/") else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
        return name.isEmpty ? nil : (bundle, name)
    }
}

extension MemoryCensus {
    /// Locations only macOS itself installs into.
    static func isSystemPath(_ path: String) -> Bool {
        ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/usr/lib/",
         "/sbin/", "/bin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }
}
