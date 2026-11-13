import AppKit
import ServiceManagement
import Foundation

/// launchd + convenience actions the UI triggers. All user-domain
/// (gui/<uid>) — exactly what a logged-in user's own process may manage.
@MainActor
public enum GuardControl {

    public static let guardLabel = "com.mac-analyzers.memory-guard"
    public static let memoryCleanLabel = "com.mac-analyzers.memory-autoclean.daily"
    public static let storageCleanLabel = "com.mac-analyzers.storage-autoclean.daily"
    public static let storageDeepLabel = "com.mac-analyzers.storage-autoclean.deep"

    /// Restart the guard agent so freshly-saved tunables take effect
    /// (the guard reads its env once at startup).
    public static func restartGuard() {
        launchctl(["kickstart", "-k", "gui/\(getuid())/\(guardLabel)"])
    }

    /// Kick an on-demand run of a scheduled job.
    public static func runNow(_ label: String) {
        launchctl(["kickstart", "gui/\(getuid())/\(label)"])
    }

    /// What a stop did, in words a person can be told.
    public enum StopResult: Equatable, Sendable {
        case stopped
        /// It had ended, or its start time changed (the pid was reused): left alone.
        case gone
        /// Not stopped on purpose, with the sentence to show.
        case refused(String)

        public var reached: Bool { self == .stopped }
    }

    /// USER-initiated stop — a different contract from the guard's automatic
    /// kills (which stay dev-tooling-only): the user may stop their own things,
    /// same as Activity Monitor. GUI apps get a graceful terminate (⌘Q semantics,
    /// save dialogs still appear); everything else gets SIGTERM.
    ///
    /// Two guards run before anything is sent. A process that belongs to a live
    /// coding session is refused (the same list the cleaners use), and the
    /// process is re-checked against `identity`, the start time it had when it
    /// was listed, so a recycled pid is refused. A process listed without an
    /// identity cannot be checked, so it is refused too.
    public static func stopProcess(_ proc: LiveProcess, identity: ProcessIdentity?) -> StopResult {
        guard let identity, identity.pid == proc.pid else {
            return .refused("\(proc.friendlyName) could not be checked before stopping, so it was left alone.")
        }
        if let agent = CodingAgentHosts.liveSessionAgent(pid: proc.pid) {
            return .refused("\(proc.friendlyName) is part of a live \(agent) session. Close the session there instead.")
        }
        guard identity.isStillRunning else { return .gone }
        if !proc.isDev,
           let app = NSRunningApplication(processIdentifier: pid_t(proc.pid)) {
            return app.terminate() ? .stopped : .gone
        }
        guard CodingAgentHosts.isAvailable else { return .refused(CodingAgentHosts.unavailableSentence) }
        // a process that hosts terminals ends every session in them when it ends
        let hosted = CodingAgentHosts.sessionsBelow(pid: proc.pid)
        if !hosted.isEmpty {
            return .refused("\(proc.friendlyName) hosts \(ProgramReach.hostedText(hosted)). Close them there instead.")
        }
        return stop([identity]).count == 1 ? .stopped : .gone
    }

    /// Quit an app: its main process gets the ⌘Q request (save prompts still
    /// appear) and its helpers leave with it. Each identity is re-checked first.
    /// A polite quit, so it does not depend on the coding-agent list.
    @discardableResult
    public static func quitApp(_ identities: [ProcessIdentity]) -> [ProcessIdentity] {
        identities.filter(quitApp)
    }

    /// USER-initiated SIGTERM of chosen processes, each only if it is still the
    /// process that was shown. Refuses everything when the coding-agent list is
    /// unavailable. For a program (a process and what it started) use `stopProgram`.
    @discardableResult
    public static func stop(_ identities: [ProcessIdentity]) -> [ProcessIdentity] {
        guard CodingAgentHosts.isAvailable else { return [] }
        return identities.filter {
            ProcessTree.signalIfSame(pid: Int32($0.pid), expected: $0.birth, signal: SIGTERM)
        }
    }

    /// What a program stop did.
    public struct ProgramStop: Sendable {
        public let asked: Int
        public let stillRunning: [ProcessIdentity]
        /// Nothing (more) was sent, and why.
        public let refusal: String?
        public var allEnded: Bool { refusal == nil && stillRunning.isEmpty }

        static func refused(_ why: String, asked: Int = 0, stillRunning: [ProcessIdentity] = []) -> ProgramStop {
            ProgramStop(asked: asked, stillRunning: stillRunning, refusal: why)
        }
    }

    /// How long a program gets to shut down after the polite request.
    public static let defaultGrace: Duration = .seconds(5)

    /// STEP ONE of stopping a program, the polite one: everything in its reach is asked to
    /// stop, deepest first, and Mac Analyzers waits. Nothing is ever killed here. What is
    /// still running afterwards is returned for the person to decide about (`forceStopProgram`).
    ///
    /// The reach is worked out from the live process table (`ProgramReach`): the listed
    /// members and what they started, never a terminal session or what is under one,
    /// never an ancestor, and nothing at all if any of it is, sits under or sits above
    /// a live coding session anywhere in its whole subtree. Each signal re-checks the
    /// process's start time.
    public static func askProgramToStop(_ listed: [ProcessIdentity], name: String = "This program",
                                        grace: Duration = defaultGrace) async -> ProgramStop {
        guard CodingAgentHosts.isAvailable else { return .refused(CodingAgentHosts.unavailableSentence) }
        let members: [ProcessIdentity]
        switch ProgramReach.compute(listed: listed, name: name) {
        case .refused(let why): return .refused(why)
        case .reach(let found): members = found
        }
        for member in members { signal(member, SIGTERM) }
        let deadline = ContinuousClock.now + grace
        while ContinuousClock.now < deadline, members.contains(where: \.isStillRunning) {
            try? await Task.sleep(for: .milliseconds(150))
        }
        return ProgramStop(asked: members.count, stillRunning: members.filter(\.isStillRunning), refusal: nil)
    }

    /// STEP TWO, only after the person chose it: the processes that did not stop are
    /// killed. Like Force Quit, it takes effect at once and the program cannot save or
    /// shut down cleanly. Before the first signal the reach is computed again from what
    /// is running now, with every rule (locks, sessions above and below, start times), so
    /// a session that appeared in the meantime refuses it.
    public static func forceStopProgram(_ stillRunning: [ProcessIdentity], name: String = "This program") async -> ProgramStop {
        guard CodingAgentHosts.isAvailable else { return .refused(CodingAgentHosts.unavailableSentence) }
        let members: [ProcessIdentity]
        switch ProgramReach.compute(listed: stillRunning, name: name) {
        case .refused(let why): return .refused(why, asked: stillRunning.count, stillRunning: stillRunning.filter(\.isStillRunning))
        case .reach(let found): members = found
        }
        for member in members { signal(member, SIGKILL) }
        try? await Task.sleep(for: .milliseconds(400))
        return ProgramStop(asked: members.count, stillRunning: members.filter(\.isStillRunning), refusal: nil)
    }

    /// Test support: the refusal a Stop on these members would give, computed without sending anything.
    @_spi(TestSupport) public static func reachRefusal(listed: [ProcessIdentity], name: String) -> String? {
        if case .refused(let why) = ProgramReach.compute(listed: listed, name: name) { return why }
        return nil
    }

    /// Test support: why this process's command line cannot be trusted yet (nil when it can).
    @_spi(TestSupport) public static func commandLineDoubt(pid: Int32) -> String? {
        CommandLineTrust.doubt(pid: pid)
    }

    /// Test support: answers the kernel read of one pid's command line with a stand-in (`.some(nil)` is "would not say");
    /// `nil` removes it. See `CommandLineTrust.standIn`.
    @_spi(TestSupport) public static func standInCommandLine(pid: Int32, _ command: String??) {
        CommandLineTrust.standIn(for: pid, command: command)
    }

    /// Test support: the rule that judges a command line, on what was read.
    @_spi(TestSupport) public static func commandLineJudgement(command: String?, parent: String?, age: TimeInterval) -> String? {
        CommandLineTrust.judge(command: command, parent: parent, age: age)
    }

    /// Test support: whether a command line is a terminal session (an interactive shell).
    @_spi(TestSupport) public static func isInteractiveShell(command: String) -> Bool {
        ProgramReach.isInteractiveShell(command: command)
    }

    /// Test support: how many processes a Stop on these members would reach right now.
    @_spi(TestSupport) public static func reachSize(listed: [ProcessIdentity], name: String) -> Int? {
        if case .reach(let found) = ProgramReach.compute(listed: listed, name: name) { return found.count }
        return nil
    }

    /// The one place a program stop sends a signal: to a process that is still
    /// the one that was identified, and never to this process or its ancestors.
    private static func signal(_ member: ProcessIdentity, _ signal: Int32) {
        #if DEBUG
        precondition(!ProgramReach.selfChain().contains(Int32(member.pid)),
                     "a program stop must never signal Mac Analyzers or an ancestor of it")
        #endif
        ProcessTree.signalIfSame(pid: Int32(member.pid), expected: member.birth, signal: signal)
    }

    /// An app gets the ⌘Q request (save prompts still appear); anything that
    /// is not a running application gets the polite stop. Never reaches a
    /// process whose start time no longer matches.
    private static func quitApp(_ identity: ProcessIdentity) -> Bool {
        guard identity.isStillRunning else { return false }
        if let app = NSRunningApplication(processIdentifier: pid_t(identity.pid)) {
            return app.terminate()
        }
        // not a running app (a command-line tool inside an app's folder): the same rule as any process,
        // which includes never ending something that hosts a live coding session
        // (a ⌘Q to a real app is the person's own and only warned about; this is a SIGTERM, so it refuses what it cannot tell)
        guard CodingAgentHosts.sessionsBelow(pid: identity.pid).isEmpty,
              CodingAgentHosts.liveSessionAgent(pid: identity.pid) == nil,
              ProgramReach.quitReach(roots: [Int32(identity.pid)]).doubt == nil else { return false }
        return stop([identity]).count == 1
    }

    /// Relaunch just this app — the light alternative to a Mac restart: the
    /// detached child survives our exit and opens a fresh instance.
    /// Set by `restartApp`, cleared when the quit is cancelled, acted on when
    /// the app is really terminating (`startRelauncherIfRequested`).
    public static var relaunchAfterQuit = false

    public static func restartApp() {
        // With a job running, quitting asks first. So Restart only RECORDS that a
        // relaunch is wanted; the relauncher starts once termination is certain
        // (the app delegate's applicationWillTerminate). Started here, it would
        // outlive a cancelled quit and relaunch the app on some later, unrelated quit.
        relaunchAfterQuit = true
        NSApp.terminate(nil)
    }

    /// Start a small shell that waits for THIS process to be gone, then opens
    /// the app again. Waiting on the pid — not a fixed pause — because stopping
    /// a running job can take a few seconds. Bounded to one minute.
    public static func startRelauncherIfRequested() {
        guard relaunchAfterQuit else { return }
        relaunchAfterQuit = false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c",
                       "n=0; while kill -0 \"$1\" 2>/dev/null && [ $n -lt 300 ]; do sleep 0.2; n=$((n+1)); done; /usr/bin/open -g \"$2\"",
                       "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        try? p.run()
    }

    /// Run the repo's upgrade.command in Terminal — visible progress: pull,
    /// rebuild, refresh agents, relaunch. Settings are never touched.
    ///
    /// `rebuildOnly` (the This Copy channel) runs `rebuild.command`: the same steps without the pull,
    /// so a clone with uncommitted work is built as it is.
    public static func runUpgrade(rebuildOnly: Bool = false) {
        NSWorkspace.shared.open(AnalyzersPaths.suiteRoot.appending(path: rebuildOnly ? "rebuild.command" : "upgrade.command"))
    }

    /// Deep-link to this app's pane in System Settings → Notifications.
    public static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Stop opening at login — part of turning the product off cleanly.
    public static func disableLoginItem() {
        try? SMAppService.mainApp.unregister()
    }

    /// Honours the same ANALYZERS_LOG_VIEWER preference the notification
    /// path uses — the in-app buttons used to ignore it and always open
    /// TextEdit, which made the Settings picker look broken.
    public static func openLog(_ url: URL) {
        let preferred = ConfigStore.currentLogViewer()
        let candidates = [
            "/System/Applications/\(preferred).app",
            "/Applications/\(preferred).app",
            "/System/Applications/Utilities/\(preferred).app",
            "/System/Applications/TextEdit.app",
        ].map { URL(fileURLWithPath: $0) }
        guard let app = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration()) { _, err in
            if err != nil { NSWorkspace.shared.open(url) }
        }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
