import AppKit
import Foundation
import Observation

/// Where the app stands against the latest release, as one observable value
/// every surface reads: the Updates screen, the status item and the menu footer.
///
/// State and API only. Today `install()` hands the work to `upgrade.command`
/// in Terminal, exactly as the Install buttons always did; the in-app updater
/// replaces what is behind `install()` without changing what the screens call.
/// The once-per-version notification stays with the update watcher in
/// `NotifierKit`, so a release is announced once, not once per reader.
@MainActor @Observable
public final class UpdateState {

    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        /// `install()` was called; the upgrade runs in Terminal and relaunches the app.
        case installing
    }

    /// The newest published version, "2.9.0"; nil until a check has answered.
    public private(set) var latest: String?
    public private(set) var phase: Phase = .idle
    /// When the last check answered, for "Checked 4 min ago".
    public private(set) var checkedAt: Date?

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
    /// The newest commit on `development` ("a1b2c3d · the commit's first line"), when Beta has heard.
    public private(set) var newestBeta: String?
    /// The changelog the channel's release notes come from: development's on Beta, the clone's on This Copy.
    public private(set) var channelChangelog: String?
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
        var list: [UpdateChannel] = [.releases]
        if hasClone && cloneBranch == "development" { list.append(.beta) }
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
    @_spi(TestSupport) public func preset(latest: String?) {
        self.latest = latest
        checkedAt = Date()
        isFixture = true
    }

    /// Set by a preset: the state is a fixture for a render, so no check overwrites it.
    @ObservationIgnored private var isFixture = false

    /// The same for a development channel: the channel, what it answered, and the clone it read.
    @_spi(TestSupport) public func preset(channel: UpdateChannel, state: ChannelState, newest: String? = nil,
                                          cloneBranch: String? = "development", facts: CloneFacts? = nil) {
        storedChannel = channel
        channelState = state
        newestBeta = newest
        hasClone = true
        self.cloneBranch = cloneBranch
        cloneFacts = facts
        checkedAt = Date()
        isFixture = true
    }

    /// Something newer than this copy exists on the channel it follows.
    public var isAvailable: Bool {
        switch channel {
        case .releases: latest.map { UpdateChecker.isNewer($0, than: installed) } ?? false
        case .beta, .thisCopy: channelState?.isUpdate ?? false
        }
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
        let found = await UpdateChecker.latestVersion(force: force)
        if let found { latest = found }
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
            var compare: BetaCompare?
            if basics.hasClone, basics.branch == "development", let commit = build.commit {
                compare = await UpdateChecker.betaCompare(installedCommit: commit, force: force)
            }
            let notes = basics.hasClone ? await UpdateChecker.betaChangelog(force: force) : nil
            guard channel == asked else { return }
            cloneDirty = dirty
            cloneFacts = nil
            channelState = ChannelLogic.beta(build: build, cloneBranch: basics.branch, isClone: basics.hasClone, compare: compare)
            newestBeta = compare?.newest
            channelChangelog = notes
        case .thisCopy:
            let read: (facts: CloneFacts?, changelog: String?) = await Task.detached {
                guard let clone = provider() else { return (nil, nil) }
                return (clone.facts(installed: build.commit), clone.changelog)
            }.value
            guard channel == asked else { return }
            cloneFacts = read.facts
            cloneDirty = read.facts?.isDirty
            channelState = ChannelLogic.thisCopy(build: build, isClone: basics.hasClone, clone: read.facts)
            channelChangelog = read.changelog
        }
    }

    /// Checks at launch and every six hours for as long as the app runs.
    /// Calling it again does nothing.
    public func startChecking() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.cadence)
            }
        }
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
            alert.informativeText = "Updating restarts Mac Analyzers, which would interrupt it. Wait for it to finish, or stop it first, then install the update."
            alert.addButton(withTitle: "Show It")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                SettingsOpener.open(target: "job:\(job.id.uuidString)")
            }
            return
        }
        // Beta pulls whatever branch the clone is on NOW: the state is up to six hours old, so look again
        if channel == .beta, cloneProvider()?.branch != "development" {
            channelState = .unavailable(Names.ChannelText.branchChanged)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = Names.ChannelText.branchChanged
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        phase = .installing
        // This Copy rebuilds the clone as it is (nothing is pulled); Releases and Beta pull, then rebuild
        GuardControl.runUpgrade(rebuildOnly: channel == .thisCopy)
    }
}
