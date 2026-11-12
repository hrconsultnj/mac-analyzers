import Foundation

/// How a log is cut into lines: on the byte 0x0A and nothing else, with one 0x0D dropped from the end of each line.
///
/// Splitting the TEXT on the Character "\n" does not cut a CRLF pair, because Swift counts "\r\n" as one Character:
/// lines of a log with Windows line endings (output a script copied in from a tool) ran together into one. The
/// `isNewline` property is no answer: it also splits on U+2028, U+2029, U+0085, form feed and vertical tab, and a
/// file name in a log line may contain one. A UTF-8 character never contains the byte 0x0A, so cutting the bytes can
/// not split one, and a lone 0x0D (not before a 0x0A) stays in its line.
public enum LogLines {

    /// Every line of `bytes` with something in it, trimmed of spaces and tabs, in order; `offsets[i]` is where line `i`
    /// begins in the file, given that `bytes` begins at `base`. For a log with LF endings the offsets are exactly
    /// those the text-based splitting gave.
    static func lines(in bytes: Data, base: UInt64 = 0) -> (lines: [String], offsets: [UInt64]) {
        var lines: [String] = []
        var offsets: [UInt64] = []
        var position = base
        for raw in bytes.split(separator: 10, omittingEmptySubsequences: false) {
            var body = raw
            if body.last == 13 { body = body.dropLast() }
            let trimmed = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { lines.append(trimmed); offsets.append(position) }
            position += UInt64(raw.count) + 1
        }
        return (lines, offsets)
    }

    static func lines(in bytes: Data) -> [String] { lines(in: bytes, base: 0).lines }

    static func lines(in text: String) -> [String] { lines(in: Data(text.utf8)) }

    /// For the probe: the same, on bytes, with where each line begins.
    @_spi(TestSupport) public static func split(_ bytes: Data, base: UInt64 = 0) -> (lines: [String], offsets: [UInt64]) {
        lines(in: bytes, base: base)
    }
}
