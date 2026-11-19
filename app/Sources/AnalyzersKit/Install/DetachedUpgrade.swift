import Darwin
import Foundation

/// Starts `upgrade.command` in its own session, with its output in a log the Updates screen reads.
///
/// There is no Terminal window. A window is what asked "terminate running processes?" when it was
/// closed, because the update was that window's shell. This process is not in the app's session, so
/// the app can quit and be opened again at the end of the script without taking the update with it.
/// Sparkle is still the updater a downloaded copy will use later; this is the same script, run here.
public enum DetachedUpgrade {

    /// Where the running update prints. Replaced at the start of each run.
    public static var logURL: URL { AnalyzersPaths.userReports.appending(path: "upgrade.log") }

    /// The new process's pid, or nil when the script is missing or could not be started.
    /// `beta` moves the clone to the newest published beta. `rebuildOnly` builds the clone as it is.
    public static func launch(rebuildOnly: Bool, beta: Bool) -> pid_t? {
        let script = AnalyzersPaths.suiteRoot.appending(path: "upgrade.command")
        guard FileManager.default.isExecutableFile(atPath: script.path) else { return nil }
        let log = logURL
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: Data())

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644) == 0,
              posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO) == 0
        else { return nil }

        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attr) }
        // A new session, so quitting the app is not delivered to the update.
        guard posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID)) == 0 else { return nil }

        var arguments = [script.path]
        if beta {
            // The person chose Beta, including when this clone is already past that beta.
            arguments.append(contentsOf: ["--beta", "--switch"])
        } else if rebuildOnly {
            arguments.append("--development")
        } else {
            arguments.append("--release")
        }
        let environment = EngineProcess.engineEnvironment().map { "\($0.key)=\($0.value)" }.sorted()
        return spawn(path: script.path, arguments: arguments, environment: environment, actions: &actions, attr: &attr)
    }

    private static func spawn(path: String, arguments: [String], environment: [String],
                              actions: inout posix_spawn_file_actions_t?,
                              attr: inout posix_spawnattr_t?) -> pid_t? {
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        let env: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) } + [nil]
        defer {
            for pointer in argv { if let pointer { free(pointer) } }
            for pointer in env { if let pointer { free(pointer) } }
        }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &actions, &attr, argv, env)
        return result == 0 ? pid : nil
    }
}
