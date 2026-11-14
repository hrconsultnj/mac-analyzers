import Foundation

/// `reports/memory/.guard-fallback.tsv`: what the app tells the guard SCRIPT and the cleanups, as plain `key<TAB>value` lines
/// they read with one awk pass under the bash macOS ships (`lib/guard-select.sh`). It can only NARROW what the scripts do:
/// the person's Never Close list (a full path or a name per line, matched as plain text, never as a pattern) and a pause. The
/// hard cap and the stop switches are NOT in it and the scripts ignore them if an old file has them: they come from the
/// managed block of config.local.sh alone, so this file can never lower a cap or turn a stop on.
public enum GuardFallbackFile {

    public static var file: URL { AnalyzersPaths.memoryReports.appending(path: ".guard-fallback.tsv") }

    /// A value the file can hold: no tab, line break or carriage return, which would split a line or start another one.
    static func safe(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("\t") && !value.contains("\n") && !value.contains("\r")
    }

    /// The file's text: paths first, then names. Anything unsafe is left out, never written in part.
    public static func contents(neverClosePaths: [String], neverCloseNames: [String], pause: Bool = false) -> String {
        var lines: [String] = []
        for path in neverClosePaths where path.hasPrefix("/") && safe(path) { lines.append("neverClosePath\t\(path)") }
        for name in neverCloseNames where !name.hasPrefix("/") && safe(name) { lines.append("neverCloseName\t\(name)") }
        lines.append("pause\t\(pause ? 1 : 0)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// A Never Close list as the person keeps it (names and paths together), split for the file.
    public static func contents(neverClose: [String], pause: Bool = false) -> String {
        contents(neverClosePaths: neverClose.filter { $0.hasPrefix("/") }, neverCloseNames: neverClose.filter { !$0.hasPrefix("/") }, pause: pause)
    }

    public static func write(neverClose: [String], pause: Bool = false, to url: URL = file) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? contents(neverClose: neverClose, pause: pause).write(to: url, atomically: true, encoding: .utf8)
    }
}
