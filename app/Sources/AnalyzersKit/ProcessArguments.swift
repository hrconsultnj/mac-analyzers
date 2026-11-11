import Foundation

/// The arguments in the buffer the kernel returns for a process (`KERN_PROCARGS2`),
/// and nothing after them.
///
/// Layout: `[argc: Int32][executable path\0][padding \0…][argv0\0][argv1\0]…[env0\0][env1\0]…`.
/// The environment follows the arguments in the same buffer, so reading one string too many
/// returns an environment variable — which can be a password or an API key.
///
/// Every argument ends with exactly ONE NUL, and an argument can be empty. A program that
/// rewrites its title (Node's `process.title`, which is how `next-server (v16.3.1)` gets its
/// name) overwrites its arguments with a shorter string and fills the rest with NULs: the
/// remaining arguments then read as EMPTY. They are still arguments and must be counted.
/// Skipping NULs to "the next string" walks past them into the environment. `ps` counts
/// terminators the same way, so this returns what `ps -o args` shows.
public enum ProcessArguments {

    public static func parse(_ bytes: UnsafeRawBufferPointer) -> [String] {
        let header = MemoryLayout<Int32>.stride
        guard bytes.count > header else { return [] }
        let argc = Int(bytes.loadUnaligned(as: Int32.self))
        var cursor = header
        // the executable's path, then the padding after it
        while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
        while cursor < bytes.count, bytes[cursor] == 0 { cursor += 1 }

        var arguments: [String] = []
        var read = 0
        while read < max(argc, 1), cursor < bytes.count {
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
            if cursor > start { arguments.append(String(decoding: bytes[start..<cursor], as: UTF8.self)) }
            cursor += 1          // this argument's own terminator, and only that one
            read += 1
        }
        return arguments
    }
}

/// A command line as it may be SHOWN: the same text with values that may be secret
/// replaced by "…". Matching (dev-tool patterns, coding agents) always uses the command
/// line itself, never this.
///
/// Two reasons a row needs it:
///  - Arguments can carry secrets on their own (`--api-key abc`, `https://user:password@host`).
///  - The reader cannot always tell arguments from environment. A program that gives itself
///    a title LONGER than its original arguments leaves no gap after it, and the kernel's
///    buffer then yields environment entries where arguments should be — to `ps` as well.
///    Nothing unprivileged says where the environment starts. So anything written
///    `NAME=value` after the program's name shows its NAME only, and so does whatever
///    follows it up to the next `NAME=`, because a value may contain spaces.
///
/// It cannot recognise every way a secret is passed (`-pVALUE`, a bare token after `-u`,
/// JSON in an argument): a command line is not a safe place for a secret, and this only
/// keeps the common shapes off the screen and the clipboard.
public enum CommandLineDisplay {

    private static let secretWords = ["key", "token", "secret", "password", "passwd", "pwd",
                                      "credential", "auth", "bearer", "private", "signature", "cookie"]

    private static func namesASecret(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return secretWords.contains { lowered.contains($0) }
    }

    /// `NAME=…` as an environment entry is written: a name of letters, digits and underscores.
    private static func assignmentName(_ token: String) -> String? {
        guard let equals = token.firstIndex(of: "="), equals != token.startIndex else { return nil }
        let name = token[..<equals]
        guard let first = name.unicodeScalars.first, first == "_" || CharacterSet.letters.contains(first),
              name.unicodeScalars.allSatisfy({ $0 == "_" || CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        return String(name)
    }

    /// What a row shows: redacted FIRST, then cut, so a cut can never leave half a secret
    /// that the redaction would have recognised whole.
    public static func shown(_ commandLine: String, limit: Int = 100) -> String {
        String(redacted(commandLine).prefix(limit))
    }

    public static func redacted(_ commandLine: String) -> String {
        let tokens = commandLine.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var shown: [String] = []
        var index = 0
        var insideValue = false          // after a NAME=, until the next NAME=
        while index < tokens.count {
            let token = tokens[index]
            if index > 0, let name = assignmentName(token) {
                shown.append(name + "=…")
                insideValue = true
            } else if insideValue {
                // the rest of a value that contained spaces: not shown
            } else if let equals = token.firstIndex(of: "="), equals != token.startIndex,
                      token.hasPrefix("-"), namesASecret(String(token[..<equals])) {
                shown.append(String(token[..<equals]) + "=…")              // --name=value
            } else if token.hasPrefix("-"), namesASecret(token),
                      index + 1 < tokens.count, !tokens[index + 1].hasPrefix("-"), !tokens[index + 1].isEmpty {
                shown.append(token)                                         // --name value
                shown.append("…")
                index += 1
            } else {
                shown.append(withoutURLPassword(token))
            }
            index += 1
        }
        return shown.joined(separator: " ")
    }

    /// `scheme://user:password@host` → `scheme://user:…@host`
    private static func withoutURLPassword(_ token: String) -> String {
        guard let scheme = token.range(of: "://"),
              let at = token[scheme.upperBound...].lastIndex(of: "@") else { return token }
        let userInfo = token[scheme.upperBound..<at]
        guard let colon = userInfo.firstIndex(of: ":"), !userInfo.contains("/") else { return token }
        return String(token[..<colon]) + ":…" + String(token[at...])
    }
}
