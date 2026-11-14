import Foundation

/// What to call a process in words, from nothing but its command line — for
/// the places that only have a line of history (a guard event, a crisis
/// report) rather than a live process. It asks the same questions the census
/// asks a live one (`LiveProcess.friendlyName`: the glossary for developer
/// tools, the app bundle for apps), so Monitor and Memory Guard never call
/// one thing two names. A path is never a name.
public enum ProcessNaming {

    /// "Node.js", "Vite dev server", "Opera", "Claude Code".
    public static func name(forCommand command: String) -> String {
        let first = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        let executable = first.split(separator: "/").last.map(String.init) ?? first
        // A coding agent is named for the product, not the file that runs it.
        if let agent = CodingAgentHosts.agent(forCommand: command) { return agent }
        if executable == "tsc" || command.contains("typescript/bin/tsc") { return "TypeScript compiler" }
        // a macOS framework's own helper reads as the framework: "Media Analysis"
        if let framework = frameworkName(in: command) { return framework }
        let isDeveloperTool = LiveStats.isDevTooling(command)
        let process = LiveProcess(pid: 0, residentMB: 0, rawName: command,
                                  kind: isDeveloperTool ? .devTool : .app)
        let name = process.friendlyName
        // the glossary says "Node.js process"; a sentence says "Node.js grew…"
        return name == "Node.js process" ? "Node.js" : name
    }

    /// "…/PrivateFrameworks/MediaAnalysis.framework/…" → "Media Analysis".
    static func frameworkName(in command: String) -> String? {
        guard command.hasPrefix("/System/"),
              let range = command.range(of: #"[^/]+(?=\.framework/)"#, options: .regularExpression)
        else { return nil }
        let raw = String(command[range])
        // split a CamelCase name into words
        var words = ""
        for (index, character) in raw.enumerated() {
            if index > 0, character.isUppercase, !(words.last?.isUppercase ?? false) { words.append(" ") }
            words.append(character)
        }
        return words
    }

    /// The project a developer tool is running for ("shop-api"), when its
    /// command line says: the folder that holds a `.git` above the first path
    /// in the command, or — when that path is gone — the folder after a
    /// conventional projects folder. nil when it names none.
    public static func project(inCommand command: String) -> String? {
        for token in command.split(separator: " ") where token.hasPrefix("/") || token.hasPrefix("~") {
            let path = (String(token) as NSString).expandingTildeInPath
            if let name = projectName(forPath: path) { return name }
        }
        return nil
    }

    static let projectFolders: Set<String> = [
        "Projects", "projects", "Developer", "developer", "dev", "Dev", "code", "Code", "src",
        "repos", "Repos", "workspace", "Workspace", "work", "Work", "GitHub", "github", "Sites",
    ]

    static func projectName(forPath path: String) -> String? {
        var parts = path.split(separator: "/").map(String.init)
        // a worktree lives INSIDE its project: <project>/.composure/workspaces/<name>
        if let marker = parts.firstIndex(of: ".composure"), marker > 0,
           parts.indices.contains(marker + 1), parts[marker + 1] == "workspaces" {
            return parts[marker - 1]
        }
        // the nearest folder above the path that is a repository — but never a
        // hidden one (~/.nvm is a git clone, and not anybody's project)
        // (and never the home folder, which some people keep under git whole)
        let home = NSHomeDirectory()
        var probe = parts
        while probe.count > 2 {
            if "/" + probe.joined(separator: "/") == home { break }
            if let name = probe.last, !name.hasPrefix("."),
               !probe.dropLast().contains(where: { $0.hasPrefix(".") }),
               FileManager.default.fileExists(atPath: "/" + probe.joined(separator: "/") + "/.git") {
                return name
            }
            probe.removeLast()
        }
        // the folder after a conventional projects folder
        if let index = parts.firstIndex(where: { projectFolders.contains($0) }), index + 1 < parts.count,
           !parts[index + 1].hasPrefix(".") {
            parts.removeSubrange(0...index)
            return parts.first
        }
        return nil
    }

    /// "Node.js in shop-api", or just the name when no project is known.
    public static func name(forCommand command: String, withProject: Bool) -> String {
        let name = name(forCommand: command)
        guard withProject, let project = project(inCommand: command) else { return name }
        return "\(name) in \(project)"
    }
}
