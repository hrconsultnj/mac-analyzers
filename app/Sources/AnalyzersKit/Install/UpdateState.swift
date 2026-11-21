import AppKit
import Darwin
import Foundation
import Observation

/// Where the app stands against the latest release, as one observable value
/// every surface reads: the Updates screen, the status item and the menu footer.
///
/// State and API only. `install()` runs `upgrade.command` in the background and the Updates
/// screen shows its lines. A downloaded copy, which has no clone to run the script on, opens
/// the latest release on GitHub. Sparkle replaces that download path later; the screens keep
/// calling `install()`.
/// The once-per-version notification stays with the update watcher in
/// `NotifierKit`, so a release is announced once, not once per reader.
@MainActor @Observable
public final class UpdateState {

    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        /// `install()` was called. The upgrade runs in the background and relaunches the app.
        case installing
    }

    /// The newest published version, "2.9.0"; nil until a check has answered.
    public private(set) var latest: String?
    public private(set) var phase: Phase = .idle
    /// Whether the last check reached GitHub: false when it could not (offline, a proxy, a limit); nil before the first answer.
    public private(set) var reachedGitHub: Bool?
    /// The newest version Beta can offer, as GitHub's list gave it ("2.73.1-beta.2", or a release newer than the beta);
    /// nil when no list was read.
    public private(set) var betaTarget: String?
    /// Whether the app checks by itself (launch and every 6 hours) and says so once per version. Saved.
    public var automaticChecks: Bool = UpdateChoices.automatic {
        didSet { UpdateChoices.automatic = automaticChecks }
    }
    /// When the last check answered, for "Checked 4 min ago".
    public private(set) var checkedAt: Date?
    /// The latest lines of an update that was started from this launch. Empty once a later check replaces them.
    public private(set) var installLines: [String] = []
    /// The update process ended and this app is still running, so it did not get as far as relaunching.
    public private(set) var installFailed = false

    public let installed: String
    /// How far this copy is from the release it is named after.
    public let build: BuildInfo

    /// What this copy follows. Saved: it survives a relaunch.
    public var channel: UpdateChannel {
        get { storedChannel }
        set {
            guard newValue != storedChannel else { return }
            storedChannel = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: UpdateChannel.defaultsKey)
            channelState = nil
            Task { await check() }
        }
    }
    private var storedChannel = UpdateChannel.saved
    /// Where Beta or This Copy leaves this copy; nil on Releases, or before the first answer.
    public private(set) var channelState: ChannelState?
    /// The newest thing Beta offers, by its short name ("2.72.1 Beta 2"), when Beta has heard; nil when no beta is out.
    public private(set) var newestBeta: String?
    /// The clone's own changelog on This Copy (its uncommitted edits included): where "Not Released Yet" comes from.
    public private(set) var channelChangelog: String?
    /// The newest published beta that is past the newest release, with the changelog as it stood at its tag: what the
    /// What's New list shows as that beta's card on Beta and This Copy. nil when no beta is out, or it is offline.
    public private(set) var betaNotes: BetaNotes?

    public struct BetaNotes: Equatable, Sendable {
        /// "2.72.1 Beta 2"
        public let label: String
        public let changelog: String
        public init(label: String, changelog: String) { self.label = label; self.changelog = changelog }
    }
    /// Whether this copy was built from a git clone, and the branch that clone is on: read with plain git,
    /// never fetched. A downloaded app has no clone and can only follow releases.
    public private(set) var hasClone = false
    public private(set) var cloneBranch: String?
    /// What the clone looks like now, for the This Copy screen.
    public private(set) var cloneFacts: CloneFacts?
    /// Whether the clone has uncommitted changes, when it was asked (Beta and This Copy); nil when unknown.
    public private(set) var cloneDirty: Bool?

    /// The channels this copy can follow, in the order the picker shows them. The one in use is always
    /// among them, so the picker never shows a selection it does not offer.
    public var channels: [UpdateChannel] {
        // Releases and Beta are always there (a beta is one click to follow; a copy that cannot install one says why and still
        // lists what the beta holds); This Copy only for a copy built from a clone
        var list: [UpdateChannel] = [.releases, .beta]
        if hasClone { list.append(.thisCopy) }
        if !list.contains(channel) { list.append(channel) }
        return list
    }

    /// The app's job store, handed over once it exists: an install restarts the
    /// app, so it must not start while a job runs.
    public weak var jobs: JobStore?

    @ObservationIgnored private var loop: Task<Void, Never>?
    private static let cadence: Duration = .seconds(6 * 3600)

    /// `installed` is the version this copy IS (`BuildInfo.version`): the release's number for a release,
    /// the development version for any other build, so a development copy is never offered the release it
    /// is already past.
    public init(build: BuildInfo = .current, clone: @escaping @Sendable () -> SourceClone? = { SourceClone.current }) {
        self.build = build
        self.installed = build.version
        self.cloneProvider = clone
    }

    /// Where the clone comes from: this app's own clone, or a throwaway one in a probe.
    @ObservationIgnored private let cloneProvider: @Sendable () -> SourceClone?

    /// For `SnapshotRunner --update-state`: sets what the last check answered, so
    /// each state of the version item can be rendered without the network.
    @_spi(TestSupport) public func preset(latest: String?, reached: Bool? = true) {
        self.latest = latest
        reachedGitHub = reached
        checkedAt = Date()
        isFixture = true
    }

    /// Set by a preset: the state is a fixture for a render, so no check overwrites it.
    @ObservationIgnored private var isFixture = false

    /// The same for a development channel: the channel, what it answered, and the clone it read.
    @_spi(TestSupport) public func preset(channel: UpdateChannel, state: ChannelState, newest: String? = nil,
                                          cloneBranch: String? = "development", facts: CloneFacts? = nil,
                                          cloneChangelog: String? = nil, betaNotes: BetaNotes? = nil,
                                          betaTargetVersion: String? = nil) {
        channelChangelog = cloneChangelog
        self.betaNotes = betaNotes
        // Kept for an ahead copy too: the screen offers that beta even when this copy is newer.
        betaTarget = betaTargetVersion
        storedChannel = channel
        channelState = state
        newestBeta = newest
        hasClone = true
        self.cloneBranch = cloneBranch
        cloneFacts = facts
        checkedAt = Date()
        isFixture = true
    }

    /// Something newer than this copy exists on the channel it follows. Notifications and the menu use this.
    /// The Updates screen uses `offersInstall`, which also offers the channel's own version when this copy is past it.
    public var isAvailable: Bool {
        switch channel {
        case .releases: latest.map { UpdateChecker.isNewer($0, than: installed) } ?? false
        case .beta, .thisCopy: channelState?.isUpdate ?? false
        }
    }

    /// The selected channel has a version this copy is not. Newer, or the stable or beta version a development
    /// copy can still install because the person chose that channel.
    public var offersInstall: Bool {
        switch channel {
        case .releases:
            guard latest != nil else { return false }
            if build.isDevelopment || build.isBeta { return true }
            return isAvailable
        case .beta:
            guard hasClone, let betaTarget else { return isAvailable }
            if build.isBeta, build.version == betaTarget { return false }
            return true
        case .thisCopy:
            return hasClone
        }
    }

    /// The Install button for the channel in use: the release, the beta, or a rebuild that names the
    /// version development is on ("Rebuild 3.2.0") — a static "Rebuild Development" said nothing about
    /// what the rebuild would produce.
    public var installTitle: String {
        switch channel {
        case .releases:
            return latest.map { "Install \(BuildInfo.label(forVersion: $0))" } ?? Names.Update.installUpdate
        case .beta:
            return betaTarget.map { "Install \(BuildInfo.label(forVersion: $0))" } ?? Names.Channel.installBeta
        case .thisCopy:
            if let development = build.developmentVersion {
                let number = development.split(separator: "-", maxSplits: 1).first.map(String.init) ?? development
                return "Rebuild \(number)"
            }
            return Names.Channel.rebuild
        }
    }

    /// The version an update would bring, on the channel in use: its internal version ("2.73.1-beta.2") for comparing and
    /// fetching its notes, and the name a person reads ("2.73.1 Beta 2"). nil when nothing newer is offered, and on This
    /// Copy, which rebuilds the clone rather than bringing a version.
    public struct Offered: Equatable, Sendable {
        public let version: String
        public let label: String
        public init(version: String) { self.version = version; self.label = BuildInfo.label(forVersion: version) }
    }

    public var offered: Offered? {
        guard isAvailable else { return nil }
        switch channel {
        case .releases: return latest.map(Offered.init(version:))
        case .beta: return betaTarget.map(Offered.init(version:))
        case .thisCopy: return nil
        }
    }

    /// The headline of the status card at the top of Updates, in the shape of the system's Software Update:
    /// "Sparehold is up to date", "Sparehold 2.73.1 Beta is available", the copy's own name for a Dev copy.
    public var statusTitle: String {
        if let offered { return "\(Names.app) \(offered.label) is available" }
        if channel == .thisCopy, isAvailable { return "Your clone has newer changes" }
        if offersInstall, channel == .releases, let latest {
            return "\(Names.app) \(BuildInfo.label(forVersion: latest))"
        }
        if offersInstall, channel == .beta, let betaTarget {
            return "\(Names.app) \(BuildInfo.label(forVersion: betaTarget))"
        }
        if phase == .checking, checkedAt == nil { return "Checking for Updates…" }
        if reachedGitHub == false, latest == nil { return "Couldn't check for updates" }
        if build.isDevelopment { return build.label }
        return "\(Names.app) is up to date"
    }

    /// The line under the headline: the installed version, or why a Dev copy has nothing to install, or that GitHub was not reached.
    public var statusDetail: String {
        if reachedGitHub == false, latest == nil { return Names.ChannelText.offline }
        if offersInstall, offered == nil, channel != .thisCopy {
            return "You have \(build.versionText)."
        }
        // Beta and Development say what THAT channel found. Releases keeps the release sentence.
        if channel != .releases, let state = channelState, offered == nil, !isAvailable {
            return state.sentence(for: channel, facts: cloneFacts)
        }
        if build.isDevelopment, offered == nil, !isAvailable {
            return build.developmentSentence(latest: latest)
        }
        return "You have \(build.versionText)."
    }

    /// What the sidebar's version item, the Updates screen and the footer call the state, one place for all
    /// three. nil until something answered (an app that cannot reach the network says only its version).
    public enum Summary: Equatable, Sendable { case updateAvailable, upToDate, developmentBuild }

    public var summary: Summary? {
        if isAvailable { return .updateAvailable }
        switch channel {
        case .releases:
            if build.isDevelopment { return .developmentBuild }
            return latest != nil ? .upToDate : nil
        case .beta, .thisCopy:
            switch channelState {
            case .upToDate?: return .upToDate
            case .ahead?: return .developmentBuild
            default: return build.isDevelopment ? .developmentBuild : (latest != nil ? .upToDate : nil)
            }
        }
    }

    /// The button the menu-bar footer shows when something is available.
    public var availableTitle: String? {
        guard isAvailable else { return nil }
        switch channel {
        case .releases: return latest.map { "Update to v\($0)" }
        case .beta: return Names.Channel.installBeta
        case .thisCopy: return Names.Channel.rebuild
        }
    }

    /// Checks now (the checker's own 6-hour cache applies unless `force`).
    public func check(force: Bool = false) async {
        guard phase != .installing, !isFixture else { return }
        phase = .checking
        let found = await UpdateChecker.latestRelease(force: force)
        if let version = found.version { latest = version }
        reachedGitHub = found.reached
        await refreshChannel(force: force)
        checkedAt = Date()
        if phase == .checking { phase = .idle }
    }

    /// Reads the clone (local git, off the main thread) and answers for the channel in use. A channel
    /// that needs the network asks GitHub's public API; none of this fetches into the person's clone.
    /// What each channel reads: Releases only whether there is a clone and its branch (the picker), Beta
    /// also whether it is dirty, This Copy everything including the fingerprint of the uncommitted changes
    /// (streamed through a hash). An answer is kept only if the channel is still the one that was asked
    /// about when it arrives: a slow check for one channel never shows under another.
    private func refreshChannel(force: Bool) async {
        let asked = channel
        let build = self.build
        let provider = cloneProvider
        let basics: (hasClone: Bool, branch: String?) = await Task.detached {
            guard let clone = provider() else { return (false, nil) }
            return (true, clone.branch)
        }.value
        hasClone = basics.hasClone
        cloneBranch = basics.branch
        guard channel == asked else { return }
        switch asked {
        case .releases:
            channelState = nil
            channelChangelog = nil
            cloneFacts = nil
            cloneDirty = nil
        case .beta:
            let dirty = await Task.detached { provider()?.isDirty }.value
            // the list and its notes are read whatever the copy is (a downloaded one sees what the beta holds); whether it can
            // INSTALL one is `ChannelLogic.beta`'s to say
            let feed = await UpdateChecker.betaFeed(force: force)
            let notes = await Self.betaNotes(from: feed, force: force)
            guard channel == asked else { return }
            cloneDirty = dirty
            cloneFacts = nil
            // a Dev copy is above every beta of its version by precedence: whether it holds the newest one is asked of GitHub
            var containment: BetaContainment?
            if build.isDevelopment, let commit = build.commit, let beta = feed?.newestBeta {
                containment = await UpdateChecker.betaContainment(tag: "v\(beta)", commit: commit, force: force)
                guard channel == asked else { return }
            }
            channelState = ChannelLogic.beta(build: build, cloneBranch: basics.branch, isClone: basics.hasClone, feed: feed,
                                             containment: containment)
            // the displayed beta follows the same rule the target does: a beta
            // behind the newest release is history, not "the newest beta" —
            // otherwise Beta advertises 2.73.1 Beta while 3.2.0 is out
            newestBeta = feed?.newestBeta.flatMap { beta in
                let pastRelease = feed?.newestRelease.map { UpdateChecker.isNewer(beta, than: $0) } ?? true
                return pastRelease ? BuildInfo.label(forVersion: beta) : nil
            }
            betaTarget = feed?.target
            channelChangelog = nil
            betaNotes = notes
        case .thisCopy:
            let read: (facts: CloneFacts?, changelog: String?) = await Task.detached {
                guard let clone = provider() else { return (nil, nil) }
                return (clone.facts(installed: build.commit), clone.changelog)
            }.value
            // the published beta's card sits under the clone's own unreleased one on This Copy
            // only a clone on development can follow a beta, so only then is the beta's card read (This Copy stays local otherwise)
            let notes = basics.hasClone && basics.branch == "development"
                ? await Self.betaNotes(from: await UpdateChecker.betaFeed(force: force), force: force) : nil
            guard channel == asked else { return }
            cloneFacts = read.facts
            cloneDirty = read.facts?.isDirty
            channelState = ChannelLogic.thisCopy(build: build, isClone: basics.hasClone, clone: read.facts)
            channelChangelog = read.changelog
            betaNotes = notes
        }
    }

    /// The newest beta, when it is past the newest release, with its changelog at its tag.
    private static func betaNotes(from feed: BetaFeed?, force: Bool) async -> BetaNotes? {
        guard let beta = feed?.newestBeta,
              feed?.newestRelease.map({ UpdateChecker.isNewer(beta, than: $0) }) ?? true,
              let text = await UpdateChecker.betaChangelog(ref: "v\(beta)", force: force)
        else { return nil }
        return BetaNotes(label: BuildInfo.label(forVersion: beta), changelog: text)
    }

    /// Checks at launch and every six hours for as long as the app runs.
    /// Calling it again does nothing.
    public func startChecking() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // switched off: no background reading (the Updates screen and "Check for Updates" still look when asked)
                if self?.automaticChecks != false { await self?.check() }
                try? await Task.sleep(for: Self.cadence)
            }
        }
    }

    /// The notes of every version between this copy and `offered` (newest first), from the changelog as it stands at the
    /// offered version's tag: what the update window lists. Empty when nothing is offered or GitHub cannot be read.
    public func notesForOffered() async -> [ReleaseNote] {
        guard let offered, let text = await UpdateChecker.betaChangelog(ref: "v\(offered.version)") else { return [] }
        return ReleaseNote.forUpdate(changelog: text, installed: installed, offered: offered.version, label: offered.label)
    }

    /// Installs the available release.
    public func install() {
        guard isAvailable else { return }
        requestInstall()
    }

    /// The one door every Install button goes through. It refuses while a job
    /// runs or waits: updating relaunches the app, which would orphan the job (or
    /// drop the waiting ones). The person is told, and can open the job.
    public func requestInstall() {
        guard phase != .installing else { return }
        if let jobs, let job = jobs.running ?? jobs.queued.first {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "A cleanup or check is running."
            alert.informativeText = "Updating restarts Sparehold, which would interrupt it. Wait for it to finish, or stop it first, then install the update."
            alert.addButton(withTitle: "Show It")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                SettingsOpener.open(target: "job:\(job.id.uuidString)")
            }
            return
        }
        // Beta checks out the published version (--switch) and leaves the branch pointer
        // where it is, including from a detached release. A dirty tree is refused by the script.
        startInstall()
    }

    /// Test support: overrides what `startInstall()` runs, so a probe can prove a non-clone or bundled-engine copy
    /// does not wedge `phase = .installing` without opening a browser or Terminal on the test machine.
    @_spi(TestSupport) @ObservationIgnored public var installHandler: (@MainActor (_ scriptURL: URL, _ rebuildOnly: Bool, _ beta: Bool) -> Bool)?

    private func startInstall() {
        guard phase != .installing else { return }
        let rebuildOnly = channel == .thisCopy
        let beta = channel == .beta
        let scriptName = rebuildOnly ? "rebuild.command" : (beta ? "beta.command" : "upgrade.command")
        let clone = cloneProvider()
        let scriptURL = (clone?.root ?? AnalyzersPaths.suiteRoot).appending(path: scriptName)
        let hasScript = !AnalyzersPaths.usingBundledEngine
            && (clone?.isWorkingTree == true)
            && FileManager.default.fileExists(atPath: scriptURL.path)
        if let installHandler {
            guard hasScript else {
                _ = installHandler(scriptURL, rebuildOnly, beta)
                return
            }
            phase = .installing
            if !installHandler(scriptURL, rebuildOnly, beta) {
                phase = .idle
            }
            return
        }
        guard hasScript else {
            if let releaseURL = URL(string: "https://github.com/hrconsultnj/sparehold/releases/latest") {
                NSWorkspace.shared.open(releaseURL)
            }
            return
        }
        phase = .installing
        installFailed = false
        installLines = []
        // Development rebuilds that branch as it is. Beta checks the published version out (--switch),
        // even when this clone is past it. Releases checks the published release out the same way.
        // The script is not a Terminal window.
        guard let pid = GuardControl.runUpgrade(rebuildOnly: rebuildOnly, beta: beta) else {
            phase = .idle
            installFailed = true
            installLines = ["The update could not be started."]
            return
        }
        watchInstall(pid)
    }

    /// Reads the update's log while it runs. When the process has gone and this app is still here, the
    /// update stopped short of relaunching, and the lines stay so the reason can be read.
    private func watchInstall(_ pid: pid_t) {
        installWatch?.cancel()
        let log = DetachedUpgrade.logURL
        installWatch = Task { [weak self] in
            while !Task.isCancelled {
                let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                let tail = Array(lines.suffix(12)).filter { !$0.isEmpty }
                self?.installLines = tail
                var status: Int32 = 0
                let waited = waitpid(pid, &status, WNOHANG)
                if waited == pid || (waited < 0 && errno == ECHILD) {
                    // One more read: the last lines are written as the process exits.
                    let finalText = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                    let finalLines = finalText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    self?.installLines = Array(finalLines.suffix(12)).filter { !$0.isEmpty }
                    // Exited, and this process is still the one that started the install.
                    // A clean finish quits and opens the new copy, the same way Restart does.
                    // Opening from the script while this process is alive does not replace it.
                    let clean = waited == pid && (status & 0x7f) == 0 && ((status >> 8) & 0xff) == 0
                    if clean {
                        GuardControl.restartApp()
                        return
                    }
                    self?.installFailed = true
                    self?.phase = .idle
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    @ObservationIgnored private var installWatch: Task<Void, Never>?
}
