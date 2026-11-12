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
/// what is being allowed. The account's numeric user ID is the only variable part: a run of digits, in single quotes.
/// Every program this path starts (`osascript`, `sudo -n -l`) gets `cleanEnvironment`, not the app's own.
public enum TimeMachinePermission {

    // MARK: - what is allowed

    /// This account's rule file, one per account (a second account's "Allow…" never replaces the first's). The
    /// name has no dot: sudo skips the files of /etc/sudoers.d whose names contain one.
    public static func ruleFile(uid: UInt32) -> String { "/etc/sudoers.d/tmutil-thin-\(uid)" }
    /// The single shared file the terminal route used to write, for whichever account ran it (by name). It is
    /// not this app's to remove: `isAllowed` still sees its effect, and the screen says how to remove it.
    public static let legacyRuleFile = "/etc/sudoers.d/tmutil-thin"
    /// The command the rule allows, and the one the engine runs. The template in the repository and the scripts say
    /// the same (a probe fails when they differ).
    public static let thinCommand = "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"

    /// Everything in the rule after the first field (who). The repository's template carries the same text after its
    /// own first field, and a probe fails when they differ.
    public static let ruleTail = "ALL=(root) NOPASSWD: \(thinCommand)"

    /// The rule's text, one line, for the account with this NUMERIC user ID: `#501 ALL=(root) NOPASSWD: …`. A number
    /// is the one part of the root command that is not a constant, and it is a run of digits nobody can choose or
    /// shape, so no quote, space, `%`, `,` or sudoers keyword can ever be in it (the manual: "user-IDs (prefixed
    /// with '#')", and a `#` followed by a user ID is not a comment).
    public static func ruleLine(uid: UInt32) -> String { "#\(uid) \(ruleTail)" }

    /// The environment every program of this path is started with: a PATH of system folders and nothing else. The
    /// app's own environment can be set by any program on the account (`launchctl setenv`), and a shell that
    /// `osascript` starts for the administrator prompt would run code named in it (an exported function called
    /// `umask`, `SHELLOPTS` with a `PS4` that runs a command) before the first word of the root command.
    public static let cleanEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]

    // MARK: - the root commands (fixed; built here, never read from a file)

    /// Root's own folder: a place only root can write, so a fixed name in it cannot be swapped by anyone else.
    static let scratch = "/private/var/root/.mac-analyzers-tmutil-thin"

    /// Writes the constant rule to a file only root can reach, has `visudo` check it, installs it in one step (mode
    /// 0440, root:wheel, `-S` so it is flushed to disk and replaced from a temporary file), and checks the live
    /// configuration: if that check fails the rule just installed is removed again, so a bad file never stays to
    /// affect every use of sudo on the Mac. Absolute paths only, no variable, no substitution, no file of ours.
    /// nil for user ID 0: root needs no rule, and a rule for `#0` would only confuse whoever reads the file.
    public static func installRootCommand(uid: UInt32) -> String? {
        guard uid != 0 else { return nil }
        let file = ruleFile(uid: uid)
        let chain = "umask 077 && /bin/rm -f \(scratch) && /usr/bin/printf '%s\\n' '\(ruleLine(uid: uid))' > \(scratch)"
            + " && /usr/sbin/visudo -cf \(scratch)"
            + " && /usr/bin/install -S -m 0440 -o root -g wheel \(scratch) \(file)"
            + " && /bin/rm -f \(scratch)"
            + " && { /usr/sbin/visudo -c || { /bin/rm -f \(file) ; exit \(sudoersBrokenStatus) ; } ; }"
        return "{ \(chain) ; } || { /bin/rm -f \(scratch) ; /usr/bin/false ; }"
    }

    /// The status the install command exits with when the final check of the live configuration fails: ANOTHER
    /// file of /etc/sudoers.d is broken (this one passed its own check), the rule just installed has been removed
    /// again, and the screen says so instead of "not changed".
    public static let sudoersBrokenStatus: Int32 = 3

    /// Removes this account's file, and only that one.
    public static func removeRootCommand(uid: UInt32) -> String? {
        uid == 0 ? nil : "/bin/rm -f \(ruleFile(uid: uid))"
    }

    // MARK: - the prompts

    /// What the administrator prompt says. Every word is true: the one command is the rule's, the whole account
    /// gets it, and the removal is on the Time Machine screen.
    public static let installPrompt = "Mac Analyzers wants to allow one command without a password: deleting Time Machine's local snapshots. From then on, any program running on this account can do that without asking. Nothing else is allowed, and you can remove the permission from the Time Machine screen in Mac Analyzers."
    public static let removePrompt = "Mac Analyzers wants to remove the permission to delete Time Machine's local snapshots without a password."

    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The AppleScript text that shows the administrator prompt and runs the install. Built here, in plain text, so a
    /// probe can print it without running it.
    public static func installAppleScript(uid: UInt32) -> String? {
        installRootCommand(uid: uid).map { "do shell script \(appleScriptString($0)) with prompt \(appleScriptString(installPrompt)) with administrator privileges" }
    }

    public static func removeAppleScript(uid: UInt32) -> String? {
        removeRootCommand(uid: uid).map { "do shell script \(appleScriptString($0)) with prompt \(appleScriptString(removePrompt)) with administrator privileges" }
    }

    /// The program that shows the prompt, set up exactly as it is run: the clean environment is part of it, so a
    /// probe reads it from here instead of trusting that `run` remembers to set it.
    public static func osascript(_ source: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.environment = cleanEnvironment
        return process
    }

    // MARK: - is it allowed

    /// Whether THIS account's rule file is on disk. /etc/sudoers.d can be searched by anyone, so no administrator is
    /// needed to see it. Only for deciding whether "Remove Permission…" is offered: whether deleting snapshots is
    /// allowed is `isAllowed`. Another account's file, or the old shared one, never counts.
    public static func ruleFileExists(uid: UInt32 = getuid()) -> Bool { FileManager.default.fileExists(atPath: ruleFile(uid: uid)) }

    /// The command that removes the old shared file, for a person to run in Terminal: the suite's own
    /// `sudoers-uninstall`, which checks that the file's rule is this account's before it removes anything. The path
    /// is the one this copy of the suite really has (the clone, or the copy inside the app when there is no clone),
    /// quoted for a shell.
    public static func uninstallCommand(suiteRoot: URL = AnalyzersPaths.suiteRoot) -> String {
        let script = suiteRoot.appending(path: "storage-analyzer/storage-manage-agents.sh").path
        return "'" + script.replacingOccurrences(of: "'", with: "'\\''") + "' sudoers-uninstall"
    }

    /// Whether the old shared file (`legacyRuleFile`) is on disk.
    public static func legacyFileExists() -> Bool { FileManager.default.fileExists(atPath: legacyRuleFile) }

    /// What `sudo -n -l` (no command) printed: true only when the entry that decides our command line is
    /// `NOPASSWD`. `sudo -l <command>` answers "permitted", which an administrator gets from `(ALL) ALL` with a
    /// password, so it cannot tell. sudo uses the LAST entry that matches, and so does this: the entries that match
    /// are `ALL`, our exact command, or `/usr/bin/tmutil` with no arguments (any arguments), and a `!` in front
    /// of one denies it. A tag is sticky along its line (`NOPASSWD: a, b`); `PASSWD:` turns it off again.
    public static func listsPasswordless(_ listing: String) -> Bool {
        var decided = false, passwordless = false
        var inList = false
        for raw in listing.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("User ") && line.contains(" may run the following commands on ") { inList = true; continue }
            guard inList, !line.isEmpty else { continue }
            var rest = Substring(line)
            var runAs = "root"
            if rest.hasPrefix("("), let close = rest.firstIndex(of: ")") {
                runAs = String(rest[rest.index(after: rest.startIndex)..<close])
                rest = rest[rest.index(after: close)...]
            }
            // `(root)`, `(ALL)`, `(root : wheel)`, `(ALL : ALL)`: the part before the colon decides whether it is root
            let users = runAs.split(separator: ":", maxSplits: 1).first.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? []
            let forRoot = users.contains("ALL") || users.contains("root")
            var tagPasswordless = false
            for item in splitEntries(String(rest)) {
                var command = item.trimmingCharacters(in: .whitespaces)
                while let colon = command.firstIndex(of: ":"), isTag(String(command[..<colon])) {
                    let tag = String(command[..<colon])
                    if tag == "NOPASSWD" { tagPasswordless = true } else if tag == "PASSWD" { tagPasswordless = false }
                    command = String(command[command.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                let denied = command.hasPrefix("!")
                if denied { command = String(command.dropFirst()).trimmingCharacters(in: .whitespaces) }
                guard forRoot, command == "ALL" || command == thinCommand || command == "/usr/bin/tmutil" else { continue }
                decided = true
                passwordless = !denied && tagPasswordless
            }
        }
        return decided && passwordless
    }

    /// A line's entries: split at "," (a comma inside a command is written `\,`).
    private static func splitEntries(_ text: String) -> [String] {
        var items: [String] = [], current = "", previous: Character = " "
        for character in text {
            if character == "," && previous != "\\" { items.append(current); current = "" } else { current.append(character) }
            previous = character
        }
        items.append(current)
        return items
    }

    private static func isTag(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "_") }
    }

    /// Whether sudo, asked as this person, would run the thinning command WITHOUT a password. It LISTS (`sudo -n -l`):
    /// nothing runs and no password is asked. Anything but a clean answer, including sudo not starting, is "not
    /// allowed yet". A rule file left by an older version, a rule for another account, or an administrator's other
    /// passwordless entry therefore never reads as our permission. `sudo` is a parameter for a probe.
    public static func isAllowed(sudo: String = "/usr/bin/sudo") async -> Bool {
        await Task.detached(priority: .userInitiated) { () -> Bool in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: sudo)
            process.arguments = ["-n", "-l"]
            process.environment = cleanEnvironment
            let output = Pipe()
            process.standardOutput = output; process.standardError = Pipe(); process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            return listsPasswordless(String(decoding: data, as: UTF8.self))
        }.value
    }

    // MARK: - asking

    public enum Outcome: Equatable, Sendable {
        case done
        case cancelled
        case failed(String)
    }

    public static let rootRefusal = "Mac Analyzers is running as the administrator (root), which needs no permission, so nothing was added or removed."

    /// Shows the macOS administrator prompt and installs the rule for THIS account (its numeric user ID). Call it only
    /// from the button the person pressed. Then asks sudo whether it works: the rule must be listed without a password.
    public static func allow(uid: UInt32 = getuid()) async -> Outcome {
        guard let source = installAppleScript(uid: uid) else { return .failed(rootRefusal) }
        let outcome = await run(source, explain: installFailureText)
        if outcome == .done, await !isAllowed() { return .failed("The permission was installed, but sudo does not list the command as allowed without a password for this account.") }
        return outcome
    }

    /// Shows its own prompt and removes THIS account's rule file. Call it only from a button the person pressed:
    /// "Remove Permission…" on the Time Machine screen, and, where Setup turns Time Machine deletion off, the same call.
    public static func revoke(uid: UInt32 = getuid()) async -> Outcome {
        guard let source = removeAppleScript(uid: uid) else { return .failed(rootRefusal) }
        return await run(source, explain: { $0 })
    }

    /// What a failed install says. Status 3 is the live configuration failing its check after the install: the
    /// error is in another file, and nothing of ours was left in place.
    public static func installFailureText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("(\(sudoersBrokenStatus))") else { return trimmed }
        let said = trimmed.dropLast("(\(sudoersBrokenStatus))".count).split(separator: "\n").last
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .map { line in line.range(of: "execution error:").map { String(line[$0.upperBound...]) } ?? line } ?? ""
        return "The permission could not be added: the sudo settings on this Mac have an error in another file, so nothing of ours was left in place, including any earlier copy of this permission."
            + (said.isEmpty ? "" : " sudo said: \(said.trimmingCharacters(in: .whitespaces))")
    }

    private static func run(_ source: String, explain: @escaping @Sendable (String) -> String) async -> Outcome {
        await Task.detached(priority: .userInitiated) { () -> Outcome in
            let process = osascript(source)
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = Pipe()
            do { try process.run() } catch { return .failed("The permission prompt could not be opened.") }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            if process.terminationStatus == 0 { return .done }
            if text.contains("-128") || text.localizedCaseInsensitiveContains("canceled") || text.localizedCaseInsensitiveContains("cancelled") { return .cancelled }
            let lastLine = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
            return .failed(explain(lastLine.isEmpty ? "It did not work." : lastLine))
        }.value
    }
}
