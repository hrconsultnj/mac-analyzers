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

    /// The app's job store, handed over once it exists: an install restarts the
    /// app, so it must not start while a job runs.
    public weak var jobs: JobStore?

    @ObservationIgnored private var loop: Task<Void, Never>?
    private static let cadence: Duration = .seconds(6 * 3600)

    public init(installed: String = UpdateChecker.installedVersion) {
        self.installed = installed
    }

    /// A newer release than the one installed exists.
    public var isAvailable: Bool {
        latest.map { UpdateChecker.isNewer($0, than: installed) } ?? false
    }

    /// Checks now (the checker's own 6-hour cache applies unless `force`).
    public func check(force: Bool = false) async {
        guard phase != .installing else { return }
        phase = .checking
        let found = await UpdateChecker.latestVersion(force: force)
        if let found { latest = found }
        checkedAt = Date()
        if phase == .checking { phase = .idle }
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
        phase = .installing
        GuardControl.runUpgrade()
    }
}
