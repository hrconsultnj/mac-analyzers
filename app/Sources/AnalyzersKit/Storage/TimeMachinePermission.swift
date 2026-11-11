import Foundation

/// The one-time permission that lets Mac Analyzers thin Time Machine's local snapshots without asking for a
/// password each time: a sudoers rule for ONE command line, `/usr/bin/tmutil thinlocalsnapshots / 999999999999 4`,
/// the exact arguments the engine uses (`tm-reclaim.sh`, `storage-auto-clean.sh`). With no wildcard, sudo matches
/// the arguments exactly: another volume, another purge amount or any other `tmutil` verb is refused.
///
/// This is the one place Mac Analyzers' code runs as root, so NOTHING a user account can write reaches root:
/// no script of ours, no template, no file under the home folder or the app bundle, no PATH lookup. The app builds
/// the whole root command from constants compiled into it (the rule's text is a constant here), as a fixed
/// sequence of absolute system paths, and shows it to macOS' administrator prompt with a prompt text that says
/// what is being allowed. The user name is the only variable part; it is validated and written in single quotes.
public enum TimeMachinePermission {

    // MARK: - what is allowed

    public static let ruleFile = "/etc/sudoers.d/tmutil-thin"
    /// The command the rule allows, and the one the engine runs. The template in the repository and the scripts say
    /// the same (a probe fails when they differ).
    public static let thinCommand = "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"

    /// The rule's text, one line, for `user`; nil for a name a rule may not be written for.
    public static func ruleLine(for user: String) -> String? {
        isValidUser(user) ? "\(user) ALL=(root) NOPASSWD: \(thinCommand)" : nil
    }

    /// A name a rule may be written for: an account name's characters, starting with a letter or underscore, never
    /// root and never the sudoers keyword ALL. Nothing that sudoers reads as a group (`%`), a user id (`#`), a
    /// list (`,`), a negation (`!`) or a new line, and no space or quote.
    public static func isValidUser(_ user: String) -> Bool {
        guard let first = user.first, first.isASCII, first.isLetter || first == "_",
              user.count <= 64, user != "root", user.uppercased() != "ALL" else { return false }
        return user.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    // MARK: - the root commands (fixed; built here, never read from a file)

    /// Root's own folder: a place only root can write, so a fixed name in it cannot be swapped by anyone else.
    static let scratch = "/private/var/root/.mac-analyzers-tmutil-thin"

    /// Writes the constant rule to a file only root can reach, has `visudo` check it, installs it (mode 0440, root:wheel)
    /// and checks the live configuration. Absolute paths only, no variable, no substitution, no file of ours.
    public static func installRootCommand(user: String) -> String? {
        guard let rule = ruleLine(for: user) else { return nil }
        let chain = "umask 077 && /bin/rm -f \(scratch) && /usr/bin/printf '%s\\n' '\(rule)' > \(scratch)"
            + " && /usr/sbin/visudo -cf \(scratch)"
            + " && /usr/bin/install -m 0440 -o root -g wheel \(scratch) \(ruleFile)"
            + " && /bin/rm -f \(scratch) && /usr/sbin/visudo -c"
        return "{ \(chain) ; } || { /bin/rm -f \(scratch) ; /usr/bin/false ; }"
    }

    /// Removes what the app installed.
    public static let removeRootCommand = "/bin/rm -f \(ruleFile)"

    // MARK: - the prompts

    public static func installPrompt(user: String) -> String {
        "Mac Analyzers wants to allow one command without a password: thinning Time Machine's local snapshots, for the account \(user). Nothing else is allowed, and you can remove it later from Setup."
    }
    public static let removePrompt = "Mac Analyzers wants to remove the permission to thin Time Machine's local snapshots without a password."

    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The AppleScript text that shows the administrator prompt and runs the install. Built here, in plain text, so a
    /// probe can print it without running it.
    public static func installAppleScript(user: String) -> String? {
        installRootCommand(user: user).map {
            "do shell script \(appleScriptString($0)) with prompt \(appleScriptString(installPrompt(user: user))) with administrator privileges"
        }
    }

    public static var removeAppleScript: String {
        "do shell script \(appleScriptString(removeRootCommand)) with prompt \(appleScriptString(removePrompt)) with administrator privileges"
    }

    // MARK: - is it allowed

    /// Whether sudo, asked as this person, would run the thinning command without a password. It LISTS the command
    /// (`sudo -n -l …`): nothing runs and no password is asked. A file left by an older version, or a rule for another
    /// account, reads as not allowed, which a file-exists test would call allowed. `sudo` is a parameter for a probe.
    public static func isAllowed(sudo: String = "/usr/bin/sudo") async -> Bool {
        await Task.detached(priority: .userInitiated) { () -> Bool in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: sudo)
            process.arguments = ["-n", "-l"] + thinCommand.split(separator: " ").map(String.init)
            process.standardOutput = Pipe(); process.standardError = Pipe(); process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
    }

    // MARK: - asking

    public enum Outcome: Equatable, Sendable {
        case done
        case cancelled
        case failed(String)
    }

    /// Shows the macOS administrator prompt and installs the rule for `user`. Call it only from the button the person
    /// pressed. Runs `/usr/bin/osascript` (the standard prompt) off the caller's thread, then asks sudo whether it works.
    public static func allow(user: String) async -> Outcome {
        guard let source = installAppleScript(user: user) else { return .failed("The permission could not be prepared for this account.") }
        let outcome = await run(source)
        if outcome == .done, await !isAllowed() { return .failed("The rule was installed, but sudo does not list the command as allowed for this account.") }
        return outcome
    }

    /// Shows its own prompt and removes the rule. Call it only from the button the person pressed (Setup's Turn Off).
    public static func revoke() async -> Outcome { await run(removeAppleScript) }

    private static func run(_ source: String) async -> Outcome {
        await Task.detached(priority: .userInitiated) { () -> Outcome in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = Pipe()
            do { try process.run() } catch { return .failed("The permission prompt could not be opened.") }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            if process.terminationStatus == 0 { return .done }
            if text.contains("-128") || text.localizedCaseInsensitiveContains("canceled") || text.localizedCaseInsensitiveContains("cancelled") { return .cancelled }
            return .failed(text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? "It did not work.")
        }.value
    }
}
