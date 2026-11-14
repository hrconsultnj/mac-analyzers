import Foundation

/// `reports/memory/.guard-fallback.tsv`: what the guard SCRIPT reads from the rules engine, as plain `key<TAB>value` lines
/// the script can read with one awk pass under the bash macOS ships (`lib/guard-select.sh`). It carries the same numbers as
/// the managed block of config.local.sh (the hard cap, whether a stop is allowed at the cap and at critical pressure) plus
/// the person's Never Close paths, which the script matches as plain text, never as a pattern. The script is the narrow
/// fallback: it knows nothing of categories or kinds and does what it always did, with those numbers.
public enum GuardFallbackFile {

    public static var file: URL { AnalyzersPaths.memoryReports.appending(path: ".guard-fallback.tsv") }

    /// The file's text. A tab or a line break in a path would split a line, so a path holding one is left out.
    public static func contents(hardCapMB: Int, hardCapStop: Bool, pressureStop: Bool, neverClosePaths: [String]) -> String {
        var lines = ["hardCapMB\t\(max(1, hardCapMB))", "hardCapStop\t\(hardCapStop ? 1 : 0)", "pressureStop\t\(pressureStop ? 1 : 0)"]
        for path in neverClosePaths where path.hasPrefix("/") && !path.contains("\t") && !path.contains("\n") && !path.contains("\r") {
            lines.append("neverClosePath\t\(path)")
        }
        lines.append("pause\t0")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func write(hardCapMB: Int, hardCapStop: Bool, pressureStop: Bool, neverClosePaths: [String], to url: URL = file) {
        let text = contents(hardCapMB: hardCapMB, hardCapStop: hardCapStop, pressureStop: pressureStop, neverClosePaths: neverClosePaths)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
