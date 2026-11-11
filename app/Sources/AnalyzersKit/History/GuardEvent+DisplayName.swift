import Foundation

extension GuardEvent {

    /// A name a person would use for the process: the glossary's name, else the
    /// app it belongs to, else the program's own name — never a path. (The log
    /// files an unknown program under its full command line, which read as
    /// "/Applications/ChatGPT.app/Contents/Resources/codex-cli/…".)
    public var displayName: String {
        if let known = ProcessGlossary.friendlyName(for: processName) { return known }
        if let app = AppBundleName.first(in: processName) { return app }
        let program = processName.split(separator: " ").first.map(String.init) ?? processName
        guard program.hasPrefix("/") else { return processName }
        return (program as NSString).lastPathComponent
    }
}
