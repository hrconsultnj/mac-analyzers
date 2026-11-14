import AppKit
import ServiceManagement
import SwiftUI
import AnalyzersKit

/// The hand-off to System Settings, for the things only System Settings can change (Full Disk Access, notifications once
/// they have been answered, approving the login item): open the exact pane, say exactly what to switch on, watch for the
/// change, and confirm when it is done.
///
/// macOS has no notification for these, so the row is read again when the app becomes active (the person has just come
/// back from System Settings) and, while the guidance is showing, every two seconds for five minutes at most.
@MainActor @Observable
final class SystemSettingsHandoff {

    /// A row that is waiting for the person to switch something on.
    struct Session: Equatable {
        let pane: SetupPane
        let started: Date
        /// The person has come back to the app and it is still not on.
        var returned = false
        /// Five minutes passed with no change.
        var timedOut = false
    }

    private(set) var sessions: [String: Session] = [:]
    /// Rows that flipped to On while being watched: they say "On, thank you" until the next read.
    private(set) var confirmed: Set<String> = []
    /// How long to watch, and how often. A probe or a render can shorten them.
    var watchFor: TimeInterval = 300
    var every: Duration = .seconds(2)
    /// The row's state, asked again.
    var reread: (SetupPane) async -> SetupItemState = { await SetupInputs.state(of: $0) }
    /// A change was seen: the screen reads everything again.
    var onChange: () async -> Void = {}

    @ObservationIgnored private var watchers: [String: Task<Void, Never>] = [:]

    /// Reads the waiting rows again each time the app becomes active: the person has just come back from System Settings.
    /// Run from the screen's `.task`, so it ends when the screen does.
    func listenForActivation() async {
        for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification).map({ _ in () }) {
            await returnedToApp()
        }
    }

    func session(_ id: String) -> Session? { sessions[id] }

    /// Opens the pane, shows the guidance in the row and starts watching.
    func begin(_ id: String, pane: SetupPane) {
        confirmed.remove(id)
        sessions[id] = Session(pane: pane, started: Date())
        open(pane)
        watchers[id]?.cancel()
        watchers[id] = Task { [weak self] in await self?.watch(id) }
    }

    /// The person closed the guidance.
    func dismiss(_ id: String) {
        watchers[id]?.cancel()
        watchers[id] = nil
        sessions[id] = nil
    }

    /// The confirmation has been seen.
    func acknowledge(_ id: String) { confirmed.remove(id) }

    private func watch(_ id: String) async {
        while !Task.isCancelled, let session = sessions[id] {
            if Date().timeIntervalSince(session.started) > watchFor {
                sessions[id]?.timedOut = true
                return
            }
            if await check(id, pane: session.pane) { return }
            try? await Task.sleep(for: every)
        }
    }

    /// Reads the row again; when it is on, confirms and closes the guidance.
    private func check(_ id: String, pane: SetupPane) async -> Bool {
        guard await reread(pane) == .on else { return false }
        confirmed.insert(id)
        sessions[id] = nil
        watchers[id]?.cancel()
        watchers[id] = nil
        await onChange()
        return true
    }

    private func returnedToApp() async {
        for (id, session) in sessions {
            sessions[id]?.returned = true
            _ = await check(id, pane: session.pane)
        }
    }

    // MARK: - opening

    /// The login item has its own documented call; everything else is the pane's one link.
    private func open(_ pane: SetupPane) {
        if pane == .loginItems { SMAppService.openSystemSettingsLoginItems(); return }
        if let url = URL(string: pane.link) { NSWorkspace.shared.open(url) }
    }

    /// Quits this app and opens it again: Full Disk Access applies to a program that was started after it was granted.
    static func quitAndReopen() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "sh", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

/// The guidance that opens in a row after Open System Settings…: exactly where to go and what to switch on, the app's
/// icon to drag into the list when the app is not in it, Show in Finder, and what the watching found.
struct SystemSettingsGuidance: View {
    let pane: SetupPane
    let session: SystemSettingsHandoff.Session
    let stillOff: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In **\(pane.path)**, \(pane.instruction).")
                .fixedSize(horizontal: false, vertical: true)
            if pane.offersDrag {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)      // the app's icon: its size is the job
                        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                        .help("Drag this icon into the list in System Settings")
                    Text("If Mac Analyzers isn't in the list, drag this icon into it, or press + and choose it in Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                if pane == .fullDiskAccess, session.returned, stillOff {
                    Button(Names.Setup.quitAndReopen) { SystemSettingsHandoff.quitAndReopen() }
                }
                Button("Not Now", action: onClose)
            }
            .controlSize(.small)
            if session.timedOut {
                Label("Still off. Check that the switch next to Mac Analyzers is on.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if session.returned, pane == .fullDiskAccess {
                Label("The switch may be on, but Full Disk Access applies to a program that starts after it was granted. If this stays off, quit and reopen Mac Analyzers.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Watching for the change…", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}
